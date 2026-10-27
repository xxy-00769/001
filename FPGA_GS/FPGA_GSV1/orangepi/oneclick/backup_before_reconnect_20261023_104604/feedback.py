"""Bounded real-EVENT feedback state. Never creates a socket or changes the wire format."""
import collections
import copy
import threading
import time
from vendor.protocol import Message, EVENT_ACK, RESULT
from vision import decide

SIMULATED = {
    'allow': (1, 0, 'SELF_TEST_ALLOW'),
    'deny': (2, 0, 'SELF_TEST_DENY'),
    'red': (2, 1, 'SELF_TEST_RED_WARNING'),
    'solid': (2, 2, 'SELF_TEST_SOLID_WARNING'),
    'unknown': (0, 0, 'SELF_TEST_UNKNOWN'),
}
ACTIONS = {1: 'KEY1 左', 2: 'KEY2 右', 3: 'KEY3 直', 4: 'KEY4 停'}


def newer(a, b):
    return 0 < ((a-b) & 0xffffffff) < 0x80000000


class EventFeedback:
    def __init__(self, session, send, lookup, frame_state, log, stats, guard=.1):
        self.session, self.send, self.lookup = session, send, lookup
        self.frame_state, self.log, self.stats, self.guard = frame_state, log, stats, guard
        self.lock = threading.RLock()
        self.mode, self.selection, self.revision = 'REAL', 'unknown', 0
        self.records = collections.deque(maxlen=32)
        self.latest_event = None
        self.pending = self.retry = None
        self.next_check = 0.
        self.counts = collections.Counter()

    def configure(self, mode, selection, now):
        if mode not in ('REAL', 'SELF_TEST') or selection not in SIMULATED:
            raise ValueError('模式或模拟判定无效')
        with self.lock:
            if (mode, selection) != (self.mode, self.selection):
                self.cancel('MODE_CHANGED', now)
                self.mode, self.selection = mode, selection
                self.revision += 1
                self.log('feedback_mode', mode_selected=mode, selection=selection,
                         revision=self.revision, applies_to='NEXT_REAL_EVENT_ONLY')
            return self.controls()

    def controls(self):
        return dict(mode=self.mode, selection=self.selection, revision=self.revision,
                    applies_to='NEXT_REAL_EVENT_ONLY', default='REAL')

    def cancel(self, reason, now):
        record = self.pending or (self.retry[1] if self.retry else None)
        if record:
            record['cancel_reason'] = reason
            record['cancelled_monotonic'] = now
            self.log('event_cancelled', session=self.session, event_id=record['event_id'],
                     frame_id=record['event_frame_id'], reason=reason)
        self.pending = self.retry = None

    def _frame(self, record, state, now):
        if state.get('received') and not record['frame_received']:
            record['frame_received'] = True
            record['frame_received_monotonic'] = state.get('received_monotonic')
            record['frame_received_before_host_deadline'] = now < record['host_deadline_monotonic']
            self.counts['exact_frame_received'] += 1
            if now > record['received_monotonic']:
                self.counts['exact_frame_received_later'] += 1
        if state.get('inference_complete'):
            if not record['inference_complete']:
                self.counts['exact_frame_inferred'] += 1
            record['inference_complete'] = True

    def frame_received(self, fid, received, now):
        with self.lock:
            for record in self.records:
                if record['event_frame_id'] == fid:
                    self._frame(record, dict(received=True, received_monotonic=received), now)

    def inference_completed(self, fid, now):
        with self.lock:
            for record in self.records:
                if record['event_frame_id'] == fid:
                    self._frame(record, dict(inference_complete=True), now)

    def event(self, msg, now):
        with self.lock:
            self._event(msg, now)

    def _event(self, msg, now):
        if msg.session != self.session:
            return
        # Always ACK immediately, including retransmissions. ACK means receipt only.
        sent = self.send(Message(EVENT_ACK, self.session, event=msg.event, frame=msg.frame))
        ack_elapsed = max(0, (time.monotonic()-now)*1000)
        self.stats['event_ack'] += 1
        if msg.code not in ACTIONS:
            self.stats['invalid_event_action'] += 1
            return
        with self.lock:
            if self.latest_event is not None and not newer(msg.event, self.latest_event):
                self.stats['duplicate_or_old_event'] += 1
                for old in self.records:
                    if old['event_id'] == msg.event:
                        old['event_ack']['attempts'] += 1
                        old['event_ack']['sent'] |= bool(sent)
                        old['duplicates'] += 1
                        break
                return
            self.cancel('NEW_EVENT', now)
            self.latest_event = msg.event
            budget = max(0, min(msg.ttl, 2000)/1000-self.guard)
            record = dict(session=self.session, event_id=msg.event, event_frame_id=msg.frame,
                          action=msg.code, action_label=ACTIONS.get(msg.code, '无效按键'),
                          board_timestamp_ms=msg.timestamp, ttl_ms=msg.ttl,
                          received_monotonic=now, host_deadline_monotonic=now+budget,
                          wait_until_monotonic=min(now+budget, now+.8),
                          decision_mode=self.mode, simulated=self.mode == 'SELF_TEST',
                          selection=self.selection, control_revision=self.revision,
                          event_ack=dict(sent=bool(sent), attempts=1,
                                         event_to_ack_send_ms=round(ack_elapsed, 3)),
                          frame_received=False, inference_complete=False,
                          result=None, result_ack=None, duplicates=0, cancel_reason=None)
            self._frame(record, self.frame_state(msg.frame, now), now)
            self.records.append(record)
            self.pending = record
            self.next_check = now
            self.stats['events'] += 1
            self.counts['events'] += 1
            self.log('event', **copy.deepcopy(record))

    def ack(self, msg, now):
        if msg.session != self.session:
            return
        with self.lock:
            # ACK.frame may be the board's current frame even for an old rejection.
            record = next((r for r in reversed(self.records) if r['event_id'] == msg.event
                           and r['result'] and r['result']['sequence'] == msg.sequence), None)
            if record is None:
                self.stats['unmatched_result_ack'] += 1
                return
            previous = record['result_ack']
            accepted = msg.code == 1
            # A duplicate rejection never revokes an earlier accepted ACK.
            retained = bool(accepted or (previous and previous['accepted']))
            if previous is None or (accepted and not previous['accepted']):
                record['result_ack'] = dict(accepted=retained, code=msg.code,
                    received_monotonic=now, event_to_ack_ms=round((now-record['received_monotonic'])*1000, 3),
                    result_to_ack_ms=round((now-record['result']['sent_monotonic'])*1000, 3),
                    after_host_deadline=now >= record['host_deadline_monotonic'])
            self.stats['result_accepted' if accepted else 'result_rejected'] += 1
            if self.retry and self.retry[1] is record:
                self.retry = None
            self.log('result_ack', session=self.session, event_id=msg.event, sequence=msg.sequence,
                     ack_frame_id=msg.frame, accepted=accepted, retained_accepted=retained,
                     event_to_ack_ms=round((now-record['received_monotonic'])*1000, 3))

    def tick(self, now):
        tick_started = time.perf_counter()
        if not (self.pending or self.retry) or now < self.next_check:
            return
        self.next_check = now+.01
        with self.lock:
            record = self.pending
            if record:
                deadline = record['host_deadline_monotonic']
                if now >= deadline:
                    record['not_sent_reason'] = 'HOST_BUDGET_EXPIRED'
                    self.counts['expired_before_result'] += 1
                    self.log('event_expired', session=self.session, event_id=record['event_id'],
                             frame_id=record['event_frame_id'], reason='HOST_BUDGET_EXPIRED')
                    self.pending = None
                else:
                    state = self.frame_state(record['event_frame_id'], now)
                    self._frame(record, state, now)
                    observation = self.lookup(record['event_frame_id'], now)
                    decision = None
                    if record['simulated']:
                        code, reason, explanation = SIMULATED[record['selection']]
                        decision = dict(code=code, reason=reason, explanation=explanation)
                    elif observation is not None:
                        decision = decide(observation, record['action'])
                    elif now >= record['wait_until_monotonic']:
                        explanation = ('EVENT_FRAME_INFERENCE_STALE' if state.get('inference_stale') else
                                       'EVENT_FRAME_INFERENCE_UNAVAILABLE' if record['frame_received'] else
                                       'EVENT_FRAME_NOT_RECEIVED')
                        decision = dict(code=0, reason=0, explanation=explanation)
                    if decision is not None and now+time.perf_counter()-tick_started < deadline:
                        result = Message(RESULT, self.session, event=record['event_id'],
                            frame=record['event_frame_id'], sequence=1,
                            ttl=min(record['ttl_ms'], 2000), code=decision['code'], reason=decision['reason'])
                        sent = self.send(result)
                        sent_now = now+time.perf_counter()-tick_started
                        record['frame_at_decision'] = dict(received=record['frame_received'],
                                                         inference_complete=record['inference_complete'])
                        if observation is not None and not record['simulated']:
                            record['evidence'] = dict(signal=copy.deepcopy(observation.get('signal',{})),
                                                      lanes=copy.deepcopy(observation.get('lanes',{})))
                        record['result'] = dict(**decision, sequence=1, ttl_ms=result.ttl,
                            sent=bool(sent), attempts=1, sent_monotonic=sent_now,
                            event_to_result_ms=round((sent_now-record['received_monotonic'])*1000, 3),
                            simulated=record['simulated'])
                        self.counts['results'] += 1
                        if not record['simulated']:
                            self.counts['real_results'] += 1
                            self.counts['real_exact_frame_results' if observation is not None
                                        else 'real_missing_inference_results'] += 1
                        self.stats['results'] += 1
                        self.log('result', session=self.session, event_id=record['event_id'],
                            frame_id=record['event_frame_id'], **copy.deepcopy(record['result']),
                            frame_at_decision=record['frame_at_decision'])
                        self.retry = (result, record, sent_now)
                        self.pending = None
            if self.retry:
                msg, record, sent_at = self.retry
                if now >= record['host_deadline_monotonic']:
                    record['ack_wait_expired'] = True
                    self.stats['result_ack_timeout'] += 1
                    self.retry = None
                elif now-sent_at >= .2:
                    sent = self.send(msg)
                    record['result']['attempts'] += 1
                    record['result']['sent'] |= bool(sent)
                    self.stats['result_retries'] += 1
                    self.retry = (msg, record, now)

    def snapshot(self, now):
        with self.lock:
            records = copy.deepcopy(list(self.records))
            controls, counts = self.controls(), dict(self.counts)
        for record in records:
            record['host_budget_remaining_ms'] = round(max(0, record['host_deadline_monotonic']-now)*1000, 1)
            record['host_budget_expired'] = now >= record['host_deadline_monotonic']
        return dict(controls=controls, recent_events=records, counts=counts,
                    history_limit=32, ttl_note='板端按事件时刻计算TTL；主机预算从首次收到EVENT起算并保留100ms余量，不能测得板端剩余TTL。',
                    latency_note='耗时仅从主机收到EVENT起算，不是物理按键到FPGA屏幕的端到端延迟。')
