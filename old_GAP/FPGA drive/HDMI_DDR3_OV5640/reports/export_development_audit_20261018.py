"""Read-only history extraction; do not export reasoning, credentials, or image data."""

import argparse
from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys


DAY = "2026-10-18"
LOCAL = timezone(timedelta(hours=8))
REPORTS = Path(__file__).resolve().parent
HOME = Path.home() / ".codex"
THREADS = {
    "01a149ed-817e-7763-97a4-deca24b31211": "推进阶段2视频与DDR集成",
    "01a14446-dfed-7811-92f4-37e45ecc0038": "梳理项目现有功能",
    "01a14960-86f5-7210-a6fa-a5a589855bac": "梳理项目现有功能（历史延续）",
    "01a149d9-bd09-78f1-915f-943412252567": "梳理项目现有功能（历史延续）",
}
REQUEST = "把今天所有的开发按照时间线完完整整的整理成.md文档"
SECRET_PATTERNS = [
    re.compile(r"\b(?:sk|hf|ghp|gho|github_pat)-?[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b"),
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)\S+"),
    re.compile(r"(?i)((?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret[_-]?key)"
               r"\s*[=:]\s*[\"']?)(?![<$%{])([A-Za-z0-9_./+=-]{12,})"),
    re.compile(r"(?i)([?&](?:tk|token|key|secret|access_token)=)[^&\s)\]\"']+"),
]


def sanitize(text):
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", str(text))
    text = "\n".join(
        "[BINARY_OR_CONTROL_CHARACTER_LINE_OMITTED]"
        if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", line) else line
        for line in text.split("\n")
    )
    text = re.sub(r"data:image/[^\s\"']+", "[IMAGE_DATA_OMITTED]", text)
    text = re.sub(r'("encrypted_content"\s*:\s*")[^"]*"', r'\1[OMITTED]"', text)
    for pattern in SECRET_PATTERNS:
        if pattern.groups:
            text = pattern.sub(lambda m: m.group(1) + "[REDACTED]", text)
        else:
            text = pattern.sub("[REDACTED]", text)
    return text


def stamp(ms):
    return datetime.fromtimestamp(ms / 1000, LOCAL).isoformat(timespec="milliseconds")


def texts(value):
    """Unwrap tool JSON text without ever serializing image/base64 fields."""
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                return texts(json.loads(value))
            except (ValueError, TypeError):
                pass
        if len(value) > 1000 and re.fullmatch(r"[A-Za-z0-9+/=\r\n]+", value):
            return "[BINARY_DATA_OMITTED]"
        return value
    if isinstance(value, list):
        return "\n".join(filter(None, (texts(v) for v in value)))
    if isinstance(value, dict):
        if value.get("type") in ("image", "input_image", "output_image"):
            return "[IMAGE_OMITTED]"
        if "text" in value:
            return texts(value["text"])
        if "content" in value:
            return texts(value["content"])
        return ""
    return ""


def connect():
    return sqlite3.connect(f"file:{(HOME / 'thread_history_1.sqlite').as_posix()}?mode=ro", uri=True)


def collect():
    connection = connect()
    connection.execute("BEGIN")
    placeholders = ",".join("?" for _ in THREADS)
    rows = connection.execute(
        f"SELECT thread_id,turn_id,item_id,rollout_ordinal,created_at_ms,item_type,item_json "
        f"FROM thread_items WHERE thread_id IN ({placeholders}) AND item_type != ? "
        "ORDER BY created_at_ms,rollout_ordinal",
        (*THREADS, "reasoning"),
    ).fetchall()
    excluded = Counter()
    items = []
    for thread, turn, item_id, ordinal, ms, kind, raw in rows:
        when = stamp(ms)
        if when[:10] != DAY:
            continue
        if kind == "contextCompaction":
            excluded["contextCompaction"] += 1
            continue
        value = json.loads(raw)
        items.append(dict(thread=thread, turn=turn, id=item_id, ordinal=ordinal,
                          ms=ms, timestamp=when, kind=kind, value=value))
    cutoffs = [r["ms"] for r in items if r["kind"] == "userMessage"
               and REQUEST in texts(r["value"].get("content", []))]
    if not cutoffs:
        raise RuntimeError("User request cutoff not found")
    cutoff = min(cutoffs)
    items = [r for r in items if r["ms"] <= cutoff]
    connection.rollback()
    connection.close()
    return items, cutoff, excluded


def user_or_agent(row):
    value = row["value"]
    if row["kind"] == "agentMessage":
        return value.get("text", "")
    if row["kind"] != "userMessage":
        return ""
    text = texts(value.get("content", []))
    if text.strip().startswith(("<environment_context>", "<turn_aborted>",
                                "Another language model started to solve this problem")):
        return ""
    return text


def outcome_excerpt(text):
    lines = text.splitlines()
    important = []
    pattern = re.compile(
        r"(error|failed|failure|exception|traceback|invalid|can't|cannot|warning|"
        r"unrouted|violat|PASS|mismatch|verify|verified|success|succeeded|WNS|WHS|"
        r"slack|returncode|exit.code|时序|失败|错误|通过|不匹配|拒绝)", re.I)
    for line in lines:
        if pattern.search(line) and line not in important:
            important.append(line[:700])
    if not important:
        important = [line[:500] for line in lines[:6]]
    selected = important if len(important) <= 18 else important[:6] + ["[MIDDLE OUTPUT OMITTED]"] + important[-12:]
    return "\n".join(selected)[:9000]


def describe(row):
    v = row["value"]
    kind = row["kind"]
    if kind == "commandExecution":
        command = v.get("command", "")
        output = v.get("aggregatedOutput", v.get("output", ""))
        if not isinstance(output, str):
            output = texts(output)
        return command, f"status={v.get('status')}; exit={v.get('exitCode')}; duration_ms={v.get('durationMs')}", output
    if kind == "fileChange":
        changes = v.get("changes", [])
        command = "\n".join(f"{c.get('kind', {}).get('type', '?')} {c.get('path')}" for c in changes)
        return command, f"status={v.get('status')}; files={len(changes)}", ""
    if kind == "mcpToolCall":
        arguments = v.get("arguments", {})
        command = f"{v.get('server')}.{v.get('tool')}\n" + json.dumps(arguments, ensure_ascii=False, indent=2)
        output = texts(v.get("result", "")) + "\n" + texts(v.get("error", ""))
        return command, f"status={v.get('status')}; duration_ms={v.get('durationMs')}", output
    if kind == "webSearch":
        return json.dumps(v.get("action", v.get("query", {})), ensure_ascii=False), str(v.get("status")), ""
    if kind == "imageView":
        return str(v.get("path", v.get("imagePath", "Image view; path not projected"))), "", ""
    return "", "", ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inspect", choices=["messages", "changes", "failures", "tools", "stats", "raw"])
    parser.add_argument("--from-time", default="00:00")
    parser.add_argument("--to-time", default="23:59")
    parser.add_argument("--grep")
    args = parser.parse_args()
    rows, cutoff, excluded = collect()
    if args.inspect == "raw":
        for path in sorted((HOME / "sessions").rglob("*.jsonl")):
            counts = Counter()
            messages = []
            with path.open(encoding="utf-8") as stream:
                for line_no, line in enumerate(stream, 1):
                    value = json.loads(line)
                    date = value.get("timestamp")
                    if not date:
                        continue
                    when = datetime.fromisoformat(date.replace("Z", "+00:00")).astimezone(LOCAL)
                    if when.date().isoformat() != DAY:
                        continue
                    payload = value.get("payload", {})
                    counts[(value.get("type"), payload.get("type"))] += 1
                    if (value.get("type") == "response_item" and payload.get("type") == "message"
                            and payload.get("role") in ("user", "assistant")):
                        phase = payload.get("phase")
                        if payload.get("role") == "assistant" and phase not in ("commentary", "final_answer", "final"):
                            continue
                        text = texts(payload.get("content", []))
                        if text.startswith(("Another language model", "<environment_context>")):
                            continue
                        messages.append(f"{when.isoformat()} line={line_no} {payload.get('role')} "
                                        f"{phase} id={payload.get('id')} {text[:500]}")
            print(path, dict(counts))
            print(sanitize("\n".join(messages)))
        return
    if args.inspect:
        print("CUTOFF", stamp(cutoff), "COUNTS", dict(Counter(r["kind"] for r in rows)))
        for r in rows:
            if not args.from_time <= r["timestamp"][11:16] <= args.to_time:
                continue
            cmd, status, output = describe(r)
            if args.grep and not re.search(args.grep, cmd + "\n" + output, re.I):
                continue
            if args.inspect == "messages" and r["kind"] in ("userMessage", "agentMessage"):
                text = user_or_agent(r)
                if text:
                    print(sanitize(f"{r['timestamp']} {r['kind']} {r['id']}\n{text}\n"))
            elif args.inspect == "changes" and r["kind"] == "fileChange":
                print(sanitize(f"{r['timestamp']} {r['id']}\n{cmd}\n{status}\n"))
            elif args.inspect == "failures" and (
                (r["kind"] == "commandExecution" and r["value"].get("exitCode") not in (0, None))
                or (r["kind"] == "mcpToolCall" and (r["value"].get("status") == "failed"
                    or re.search(r"DesignEditor-00|can't find load|no screenshot|invalid arguments", output)))
            ):
                print(sanitize(f"{r['timestamp']} {r['id']}\n{cmd}\n{status}\n{outcome_excerpt(output)}\n"))
            elif args.inspect == "tools" and r["kind"] not in ("userMessage", "agentMessage"):
                short = cmd if len(cmd) < 1400 else cmd[:1400] + "\n[INSPECT DISPLAY TRUNCATED]"
                print(sanitize(f"{r['timestamp']} {r['id']}\n{short}\n{status}\n{outcome_excerpt(output)[:1800]}\n"))
        return

    messages = [r for r in rows if user_or_agent(r)]
    msgpath = REPORTS / f"{DAY}_完整对话记录.md"
    lines = [f"# {DAY} 完整可见对话记录", "",
             f"- 截止：{stamp(cutoff)}，包含本次整理请求，不递归收入整理过程。",
             "- 时间统一为本机 UTC+08:00；环境声明 America/New_York 与此不同，主报告另有说明。",
             "- 来源：本地 thread_history_1.sqlite 只读事务快照；仅项目相关会话。",
             "- 排除内部推理、压缩摘要、系统/开发者指令、图像编码；凭据与链接令牌脱敏。",
             "- 助手原话只表示当时的表述，不能代替构建或实机证据。",
             f"- 可见消息共 {len(messages)} 条。", ""]
    for n, r in enumerate(messages, 1):
        who = "用户" if r["kind"] == "userMessage" else f"助手 {r['value'].get('phase', '')}"
        lines.extend([f"## M{n:03d} | {r['timestamp'][11:23]} | {who}", "",
                      f"来源会话：{THREADS[r['thread']]}；记录 ID：`{r['id']}`。", "",
                      sanitize(user_or_agent(r)), "", "---", ""])
    msgpath.write_text("\n".join(lines), encoding="utf-8")

    toolpath = REPORTS / f"{DAY}_操作逐项审计.md"
    lines = [f"# {DAY} 操作逐项审计", "",
             f"- 截止：{stamp(cutoff)}；本文件按实际发出的操作排序，不包含内部推理。",
             "- 命令/参数保留，工具输出仅摘录状态和关键行，不重复复制整份源码、二进制或截图。",
             "- shell 返回 0 不保证 FPGA 时序或验收通过；查询无匹配返回 1 也不一定是功能失败。",
             "- 脱敏及二进制/控制字符省略会改变导出文字；原始记录规范化哈希另见 JSON 索引。",
             "- UI 的 type_text 只代表输入；需后续 Return 和工具输出才能确认实际执行。",
             "- fileChange 记录包含路径与增删改类型；历史补丁完整内容保留在本地会话库，不批量外传。",
             "- action 时间来自投影创建时间，可能是完成后入库，不声称是精确开始时间。",
             "- 下列路径保留历史原文；归档后的现存路径对照见主报告。", ""]
    operations = []
    for r in rows:
        if r["kind"] in ("userMessage", "agentMessage"):
            continue
        cmd, status, output = describe(r)
        n = len(operations) + 1
        operations.append(dict(index=n, id=r["id"], timestamp=r["timestamp"], kind=r["kind"],
                               thread=r["thread"], status=status))
        fence = "````"
        lines.extend([f"## O{n:04d} | {r['timestamp'][11:23]} | {r['kind']}", "",
                      f"记录 ID：`{r['id']}`；会话：{THREADS[r['thread']]}。", "",
                      status, "", fence + "text", sanitize(cmd), fence, ""])
        excerpt = outcome_excerpt(output)
        if excerpt.strip():
            lines.extend(["输出摘录：", "", fence + "text", sanitize(excerpt), fence, ""])
    toolpath.write_text("\n".join(lines), encoding="utf-8")

    reportpath = REPORTS / f"{DAY}_开发完整时间线与问题复盘.md"
    outputpaths = [msgpath, toolpath]
    if reportpath.exists():
        outputpaths.append(reportpath)
    manifest = {
        "day": DAY, "timezone": "+08:00", "cutoff": stamp(cutoff),
        "generated_at": datetime.now(LOCAL).isoformat(timespec="seconds"),
        "source": str(HOME / "thread_history_1.sqlite"),
        "source_access": "read-only SQLite transaction; not modified or copied",
        "threads": THREADS, "counts": dict(Counter(r["kind"] for r in rows)),
        "visible_messages": len(messages), "operations": len(operations),
        "excluded": dict(excluded), "redacted": True, "includes_reasoning": False,
        "outputs": [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                     "bytes": p.stat().st_size} for p in outputpaths],
        "message_index": [dict(index=n, id=r["id"], timestamp=r["timestamp"], thread=r["thread"])
                          for n, r in enumerate(messages, 1)],
        "operation_index": operations,
        "record_hashes": [
            {"id": r["id"], "sha256": hashlib.sha256(
                json.dumps(r["value"], ensure_ascii=False, sort_keys=True).encode("utf-8")
            ).hexdigest()} for r in rows
        ],
    }
    (REPORTS / f"{DAY}_开发审计索引.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ("cutoff", "counts", "visible_messages", "operations", "outputs")},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
