"""Image-derived paint semantics. Geometry is a model-guided search, never a label.

No scene names, timestamps, manually drawn lane ROIs or direction inference.
Missing/occluded paint is NOT dashed evidence. Output is a crossing restriction,
not traffic clearance. Short temporal confirmation is bounded to 0.65 seconds.
"""
import copy, time, collections
import cv2
import numpy as np


def unknown(reason):
    return dict(state='UNKNOWN', raw_state='UNKNOWN', reason=reason,
                adjacent=dict(state='UNKNOWN', reason='没有独立外侧边界与道路走廊证据'),
                confidence=None, evidence={})


def runs(a):
    e = np.diff(np.r_[False, a, False].astype(np.int8))
    return list(zip(np.where(e == 1)[0], np.where(e == -1)[0]))


class LaneSemantics:
    def __init__(self):
        self.reset()

    def reset(self):
        self.history = {s: collections.deque(maxlen=6) for s in ('left', 'right')}
        self.previous = None
        self.previous_at = 0
        self.pending = None
        self.adjacent_history={s:collections.deque(maxlen=5) for s in ('left','right')}

    def evidence(self, curve, gray, contrast, paint, occlusion, broad=False):
        """Sample native-RGB-derived ridges along a model curve at 960px width.

        A paint row needs a narrow bright ridge with TWO local shoulders. This
        excludes most kerbs and shadow steps. Large transverse markings are
        rejected by width, longitudinal consistency and model support upstream.
        """
        h, w = gray.shape
        lo, hi = max(.47, curve['ymin']), min(.88, curve['ymax'])
        if hi-lo < .16:
            return None
        ys = np.arange(int(lo*h), int(hi*h)+1, 2)
        pred = np.polyval(curve['fit'], ys/h)*w
        radius = int(w*(.025 if not broad else .065))
        found = np.full(len(ys), np.nan); values = np.zeros(len(ys))
        blocked = np.zeros(len(ys), bool)
        for i, (y, xp) in enumerate(zip(ys, pred)):
            xp = int(round(xp)); a = max(1, xp-radius); b = min(w-2, xp+radius+1)
            if b-a < 4: continue
            if occlusion[y, max(0,xp-int(w*.012)):min(w,xp+int(w*.012)+1)].any():
                blocked[i] = True; continue
            row = contrast[y, a:b]
            opts = []
            for p,q in runs(row >= 17):
                if not 1 <= q-p <= w*.024: continue
                x = a+(p+q-1)/2
                # Need lane paint in model neighbourhood or an explicitly
                # searched adjacent corridor. A strong step is not a ridge.
                if not broad:
                    xx=int(x/3); yy=int(y*180/h)
                    if not paint[max(0,yy-4):min(180,yy+5),max(0,xx-9):min(320,xx+10)].any():continue
                score = float(row[p:q].max()) - abs(x-xp)*.38
                opts.append((score,x,float(row[p:q].max())))
            if opts:
                _, found[i], values[i] = max(opts)
        good=np.isfinite(found)
        if good.sum()<10 or np.ptp(ys[good])/h<.15:return None
        fit=np.polyfit(ys[good]/h,found[good]/w,2)
        residual=np.abs(found/w-np.polyval(fit,ys/h))
        good &= residual < .008
        if good.sum()<10 or np.ptp(ys[good])/h<.15:return None
        fit=np.polyfit(ys[good]/h,found[good]/w,2)
        # Only retain pixels near the final RGB curve; segmentation gaps are
        # observable RGB gaps only when road background remains visible.
        good &= np.abs(found/w-np.polyval(fit,ys/h)) < .008
        visible=~blocked
        coverage=float(good.sum()/max(1,visible.sum()))
        # Fill at most one sampled row (4 native-ish px), not missing dashes.
        cleaned=good.copy()
        for j in range(1,len(good)-1):
            if good[j-1] and good[j+1] and not blocked[j]:cleaned[j]=True
        segments=[(a,b) for a,b in runs(cleaned) if b-a>=2]
        gaps=[]
        for (_,a),(b,_) in zip(segments,segments[1:]):
            if b-a>=3 and not blocked[max(0,a-1):min(len(ys),b+1)].any():gaps.append((a,b))
        span=(ys[-1]-ys[0])/h
        max_gap=max((b-a for a,b in runs(~cleaned & visible)),default=0)*2/h
        raw='UNKNOWN';reason='标线可见长度或连续/间隔证据不足'
        if span>=.19 and coverage>=.84 and max_gap<=.025 and blocked.mean()<.15:
            raw='SOLID';reason='原图窄标线连续，模型引导＋两侧亮度脊线'
        elif span>=.21 and len(segments)>=3 and len(gaps)>=2 and .18<coverage<.78 and blocked.mean()<.08:
            # A dashed verdict requires repeated clean asphalt gaps. An object
            # or dark abrupt lighting change vetoes it, never creates it.
            bg=[]
            # Include leading/trailing missing paint too: a shadow must not
            # disappear from the evidence simply because it erased the first
            # qualifying dash. Every observed absence needs readable asphalt.
            for j in np.where(~cleaned & visible)[0]:
                y=ys[j];x=int(np.clip(np.polyval(fit,y/h)*w,6,w-7))
                bg.append(float(np.median(gray[y,x-5:x+6])))
            if bg and np.percentile(bg,10)>40 and np.percentile(bg,90)-np.percentile(bg,10)<85:
                raw='DASHED';reason='原图至少三段纵向标线、两段可见路面间隔；待时序确认'
        obs_y=ys[good]/h
        pts=np.c_[np.polyval(fit,np.linspace(obs_y.min(),obs_y.max(),40)),np.linspace(obs_y.min(),obs_y.max(),40)]
        refined=dict(curve, fit=fit.tolist(),points=pts.round(5).tolist(),ymin=float(obs_y.min()),ymax=float(obs_y.max()),
                     model_fit=curve['fit'],source='YOLOP_GUIDED_RGB_RIDGE',rgb_shift=round(float(np.median(np.abs(np.polyval(fit,obs_y)-np.polyval(curve['fit'],obs_y)))),5))
        return dict(raw_state=raw,reason=reason,curve=refined,
                    evidence=dict(rgb_coverage=round(coverage,3),paint_runs=len(segments),clean_gaps=len(gaps),occluded_fraction=round(float(blocked.mean()),3),observed_span=round(float(span),3),max_visible_gap=round(float(max_gap),3),
                                  sample_y=(ys/h).round(4).tolist(),paint_present=good.astype(int).tolist(),occluded=blocked.astype(int).tolist()))

    def analyze(self, image, road_result, masks, boxes=None, now=None):
        t=time.perf_counter();now=time.monotonic() if now is None else now
        ego=road_result['ego'];model_ego=copy.deepcopy(ego)
        result=dict(left=unknown('本车道尚未确认'),right=unknown('本车道尚未确认'),
                    visible_lane_count=None,ego_ordinal=None,confirmed_corridors=0,
                    numbering_basis='不能确认完整可见车道集合与最左起点；序号未知',
                    direction_relation='UNKNOWN',direction_reason='标线颜色/单帧车头方向不能证明同向或对向',
                    method='YOLOP二值标线引导＋960宽RGB脊线＋道路几何＋短时投票；非车道实例模型')
        road_result['model_ego']=model_ego
        reacquired=False
        if ego.get('state')!='DETECTED' and self.previous and now-self.previous_at<.35:
            # A previous curve is ONLY a search seed. Both edges still need
            # new RGB ridges AND neighbourhood support in this frame's model
            # paint. No previous polygon is published as current detection.
            ego=copy.deepcopy(self.previous);ego.update(state='SEARCH_SEED',polygon=[])
            road_result['ego']=ego;reacquired=True
        if ego.get('state') not in ('DETECTED','SEARCH_SEED') and not any(ego.get(s) for s in ('left','right')):
            self.history={s:collections.deque(maxlen=6) for s in ('left','right')}
            self.previous=None
            result['reason']=ego['reason'];road_result['lane_semantics']=result
            road_result['stage_ms']['lane_semantics']=round((time.perf_counter()-t)*1000,2)
            return
        hh,ww=image.shape[:2];h=round(hh*960/ww);rgb=cv2.resize(image,(960,h))
        gray=cv2.cvtColor(rgb,cv2.COLOR_BGR2GRAY)
        # Horizontal top-hat extracts narrow light paint on locally darker road;
        # yellow remains bright in luminance. Colour is never a direction label.
        contrast=cv2.morphologyEx(gray,cv2.MORPH_TOPHAT,cv2.getStructuringElement(cv2.MORPH_RECT,(41,1)))
        occlusion=np.zeros((h,960),np.uint8)
        for obj in boxes or []:
            x0,y0,x1,y1=np.asarray(obj['box'])*[960/ww,h/hh,960/ww,h/hh]
            cv2.rectangle(occlusion,(max(0,int(x0)-9),max(0,int(y0)-5)),(min(959,int(x1)+9),min(h-1,int(y1)+8)),255,-1)
        current={}
        for side in ('left','right'):
            ev=self.evidence(ego[side],gray,contrast,masks[1],occlusion) if ego.get(side) else None
            current[side]=ev
            if not ev:
                result[side]=unknown('RGB标线复查失败；不能把分割边缘当成实虚线')
                continue
            ego[side]=ev['curve']
        # Reject sudden selection switches until repeated independent evidence.
        if self.previous and now-self.previous_at<.5 and all(ego.get(s) for s in ('left','right')):
            jump=max(abs(np.polyval(ego[s]['fit'],.72)-np.polyval(self.previous[s]['fit'],.72)) for s in ('left','right'))
            if jump>.075:
                repeated=self.pending and max(abs(np.polyval(ego[s]['fit'],.72)-np.polyval(self.pending[s]['fit'],.72)) for s in ('left','right'))<.03
                if not repeated:
                    self.pending=copy.deepcopy(ego);ego.update(state='UNKNOWN',polygon=[],reason='边界位置跳变，等待独立确认')
                    self.history={s:collections.deque(maxlen=6) for s in ('left','right')}
                    road_result['lane_semantics']=result;road_result['stage_ms']['lane_semantics']=round((time.perf_counter()-t)*1000,2);return
        self.pending=None
        # Polygon uses shared OBSERVED span only, with no road-intersection extension.
        both=all(ego.get(s) for s in ('left','right'))
        lo=max(ego[s]['ymin'] for s in ('left','right')) if both else 0;hi=min(ego[s]['ymax'] for s in ('left','right')) if both else 0
        ys=np.linspace(lo,hi,35);lx=np.polyval(ego['left']['fit'],ys) if both else np.zeros(35);rx=np.polyval(ego['right']['fit'],ys) if both else np.zeros(35)
        paired=both and not (hi-lo<.15 or np.any(rx-lx<.025) or np.any(rx-lx>.85) or any(current[s] is None for s in current))
        if not paired:
            ego.update(state='UNKNOWN',polygon=[],reason='原图复查无法确认成对边界')
            result['reason']=ego['reason']
        if paired:
            ego['state']='DETECTED';ego['search_seed']='temporal_current_RGB_revalidated' if reacquired else 'current_YOLOP'
            ego['polygon']=np.r_[np.c_[lx,ys],np.c_[rx,ys][::-1]].round(5).tolist()
            ego['reason']='YOLOP模型边界经原图窄标线复查；仅绘制共同观测范围'
            result['confirmed_corridors']=1
            self.previous=copy.deepcopy(ego);self.previous_at=now
        # A weak opposite edge must not erase current evidence on THIS edge.
        # Both types remain independently visible, but unpaired geometry cannot
        # authorize any crossing advice or create a filled ego polygon.
        for side in ('left','right'):
                ev=current[side];hist=self.history[side]
                if ev is None:
                    result[side]=unknown('该侧原图标线观察太短/遮挡，实虚未知');continue
                # Raw UNKNOWN cancels confirmed state immediately; no long hold.
                while hist and now-hist[0][0]>.65:hist.popleft()
                hist.append((now,ev['raw_state']))
                n=sum(x[1]==ev['raw_state'] for x in hist)
                opposite='SOLID' if ev['raw_state']=='DASHED' else 'DASHED'
                stable=ev['raw_state']!='UNKNOWN' and n>=3 and not any(x[1]==opposite for x in hist)
                result[side]=dict(state=ev['raw_state'] if stable else 'UNKNOWN',raw_state=ev['raw_state'],reason=ev['reason'] if stable or ev['raw_state']=='UNKNOWN' else '当前像素候选，等待至少三次同类观测',evidence=ev['evidence'],temporal_votes=n,confidence=None,
                                  ownership='PAIRED_EGO' if paired else 'CANDIDATE_NOT_PAIRED',
                                  adjacent=dict(state='UNKNOWN',reason='缺少独立外侧标线；不能把路肩/对向道路当成可变车道'))
                # Search for an actual OUTER ridge within a perspective-consistent
                # corridor. Predicted coordinates are search centres, never output.
                if not paired:continue
                sign=-1 if side=='left' else 1
                predicted=np.asarray(ego[side]['fit'])+sign*(np.asarray(ego['right']['fit'])-np.asarray(ego['left']['fit']))
                probe=dict(fit=predicted.tolist(),ymin=lo,ymax=hi)
                outer=self.evidence(probe,gray,contrast,masks[1],occlusion,broad=True)
                if outer:
                    yy=np.linspace(max(lo,outer['curve']['ymin']),min(hi,outer['curve']['ymax']),20)
                    inner_x=np.polyval(ego[side]['fit'],yy);outer_x=np.polyval(outer['curve']['fit'],yy);width=np.abs(outer_x-inner_x);ego_w=np.polyval(ego['right']['fit'],yy)-np.polyval(ego['left']['fit'],yy)
                    between=np.concatenate([np.c_[(inner_x*(1-f)+outer_x*f),yy] for f in [.2,.4,.6,.8]])
                    in_image=bool(np.all((between[:,0]>.01)&(between[:,0]<.99)))
                    xx=np.clip((between[:,0]*320).astype(int),0,319);yyy=np.clip((between[:,1]*180).astype(int),0,179)
                    support=float(np.mean(masks[0][yyy,xx]>0))
                    result[side]['adjacent']['candidate_evidence']=dict(rgb=outer['raw_state'],road_support=round(support,3),width_ratio=round(float(np.median(width/ego_w)),3),in_image=in_image)
                    # Existence of a geometric corridor does not require us to
                    # know whether its OUTER paint is solid or dashed. Keep
                    # those distinct; require repeat current-image geometry.
                    outer_ev=outer['evidence'];visible_ridge=outer_ev['rgb_coverage']>.22 and (outer_ev['paint_runs']>=2 or outer_ev['rgb_coverage']>.8)
                    if in_image and len(yy)>0 and .52<np.median(width/ego_w)<1.65 and np.all((outer_x-inner_x)*sign>.03) and support>.82 and visible_ridge:
                        history=self.adjacent_history[side]
                        while history and now-history[0][0]>.65:history.popleft()
                        pos=float(np.polyval(outer['curve']['fit'],.65));history.append((now,pos))
                        if len(history)>=3 and max(x[1] for x in history)-min(x[1] for x in history)<.03:
                            result[side]['adjacent']=dict(state='EXISTS',reason='原图外侧纵向标线＋透视宽度＋道路走廊，三次复查；通行方向仍未知',road_support=round(support,3),outer=outer['curve'],evidence=outer_ev)
                            result['confirmed_corridors']+=1
        if paired:result['reason']='可见局部走廊有几何证据；不推断道路总车道数或同向/对向'
        road_result['lane_semantics']=result
        road_result['stage_ms']['lane_semantics']=round((time.perf_counter()-t)*1000,2)
