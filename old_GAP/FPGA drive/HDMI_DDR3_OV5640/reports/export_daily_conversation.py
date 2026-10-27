"""Export visible messages for this thread only; exclude reasoning and tool internals."""
import argparse
from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re


THREAD = "01a14446-dfed-7811-92f4-37e45ecc0038"
DAY = "2026-10-17"
LOCAL = timezone(timedelta(hours=8))
REPORTS = Path(__file__).resolve().parent
REQUEST = "先把今天所有的对话内容和你做过的事情整理成.md文档"
CONTEXT_SUMMARY = re.compile(
    r"^(?:#{1,3}\s+|\*\*)(?:Active (?:Task|Goal|Request)|Current Task|"
    r"Latest Request / Pending Reply)(?:\b|[ *])"
)


def text_content(content):
    parts = []
    images = 0
    for part in content:
        if part.get("type") in ("input_text", "output_text", "text"):
            parts.append(part.get("text", ""))
        elif part.get("type") in ("input_image", "image"):
            images += 1
    return "\n\n".join(parts).strip(), images


def visible_user(text):
    stripped = text.strip()
    if stripped.startswith(("<environment_context>", "<turn_aborted>")):
        return False
    return not stripped.startswith("Another language model started to solve this problem")


def normalize_attachment_message(text, images):
    inline_paths = re.findall(r'<image name=\[Image #\d+\] path="([^"]+)">', text)
    text = re.sub(
        r'<image name=\[Image #\d+\] path="[^"]+">\s*</image>', "", text
    ).strip()
    marker = "## My request:"
    if text.startswith("# Files mentioned by the user:") and marker in text:
        files_text, body = text.split(marker, 1)
        files = re.findall(r"^## ([^\r\n]+)", files_text, re.MULTILINE)
        attachment_lines = []
        for item in files:
            name, sep, path = item.partition(": ")
            attachment_lines.append(f"- `{name}`" + (f"：`{path}`" if sep else ""))
        text = body.strip() or "（仅发送附件，没有附加文字。）"
        if attachment_lines:
            text += "\n\n附件：\n" + "\n".join(attachment_lines)
    elif inline_paths:
        text = (text + "\n\n" if text else "（仅发送附件，没有附加文字。）\n\n")
        text += "附件：\n" + "\n".join(f"- `{path}`" for path in inline_paths)
    elif images:
        text = (text + "\n\n" if text else "") + f"（另含 {images} 个图像内容项；不导出内嵌图像编码。）"
    return text


def collect():
    sessions = Path.home() / ".codex/sessions"
    paths = sorted(sessions.glob(f"2026/10/*/*{THREAD}*.jsonl"))
    assert paths, "The current thread's local logs were not found"
    messages = {}
    excluded = Counter()
    failures = []
    sources = []
    for path in paths:
        data = path.read_bytes()
        sources.append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
        for lineno, line in enumerate(data.decode("utf-8").splitlines(), 1):
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                failures.append({"path": str(path), "line": lineno})
                continue
            if row.get("type") != "response_item":
                continue
            payload = row.get("payload", {})
            if payload.get("type") != "message" or payload.get("role") not in ("user", "assistant"):
                continue
            stamp = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
            local = stamp.astimezone(LOCAL)
            if local.date().isoformat() != DAY:
                continue
            role, phase = payload["role"], payload.get("phase")
            if role == "assistant" and phase not in ("commentary", "final_answer", "final"):
                excluded["nonvisible_assistant_channels"] += 1
                continue
            text, images = text_content(payload.get("content", []))
            if role == "assistant" and CONTEXT_SUMMARY.match(text):
                excluded["context_handoff_summaries"] += 1
                continue
            if role == "user" and not visible_user(text):
                excluded["injected_context_messages"] += 1
                continue
            if not text and not images:
                excluded["empty_messages"] += 1
                continue
            key = payload.get("id") or (row["timestamp"], role, phase, text)
            if key in messages:
                excluded["replayed_message_ids"] += 1
                continue
            messages[key] = {
                "id": payload.get("id"), "timestamp": local.isoformat(), "role": role,
                "phase": phase, "text": normalize_attachment_message(text, images) if role == "user" else text,
                "source": str(path), "line": lineno,
            }
    ordered = sorted(messages.values(), key=lambda item: item["timestamp"])
    stops = [item["timestamp"] for item in ordered if item["role"] == "user" and REQUEST in item["text"]]
    assert stops, "The audit request cutoff could not be found"
    cutoff = min(stops)
    ordered = [item for item in ordered if item["timestamp"] <= cutoff]
    return ordered, sources, dict(excluded), failures, cutoff


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    messages, sources, excluded, failures, cutoff = collect()
    assert not failures, f"Unparsed log rows: {failures}"
    counts = Counter("user" if item["role"] == "user" else item["phase"] for item in messages)
    if args.inspect:
        print(json.dumps({"count": len(messages), "counts": dict(counts), "cutoff": cutoff,
                          "source_files": sources, "excluded": excluded}, ensure_ascii=False, indent=2))
        for number, item in enumerate(messages, 1):
            if item["role"] == "user" or item["phase"] in ("final_answer", "final"):
                text = item["text"].replace("\n", " ")
                print(f"{number:03d} {item['timestamp'][11:19]} {item['role']} {text[:380]}")
        return
    output = REPORTS / f"{DAY}_完整对话记录.md"
    heading = [
        f"# {DAY} 完整对话记录",
        "",
        "- 范围：当前聊天“梳理项目现有功能”，不是电脑上的其他聊天。",
        "- 时间：按本机日志转换为 UTC+08:00；不把目录名或助手的口头日期当作原始时间。",
        f"- 截止：{cutoff}，包含你要求整理文档的这条消息；不循环收入整理过程。",
        f"- 共 {len(messages)} 条可见消息：用户 {counts['user']} 条，助手进度说明 "
        f"{counts['commentary']} 条，助手正式答复 {counts['final_answer'] + counts['final']} 条。",
        "- 正文保留消息文字；附件统一列出原文件名/路径，不包含图片的二进制内容。",
        "- 不包含内部推理、上下文交接摘要、系统/开发者指令、工具调用原始数据或凭据。",
        "- 本附录记录助手当时说了什么，不替助手的结论背书；实际完成情况见工作复盘。",
        "- 某些工具中的澄清问题以用户提交的问答 JSON 原样保留。",
        "",
        f"[返回工作复盘](/{(REPORTS / f'{DAY}_工作复盘.md').as_posix()})",
        "",
    ]
    for number, item in enumerate(messages, 1):
        who = "用户" if item["role"] == "user" else "助手进度说明" if item["phase"] == "commentary" else "助手答复"
        heading.extend([f"## {number:03d} · {item['timestamp'][11:19]} · {who}", "",
                        item["text"], "", "---", ""])
    output.write_text("\n".join(heading), encoding="utf-8")
    manifest = {
        "day": DAY, "timezone": "+08:00", "thread_id": THREAD, "cutoff": cutoff,
        "message_count": len(messages), "counts": dict(counts), "excluded": excluded,
        "parse_errors": failures, "source_files_snapshot": sources,
        "output": str(output), "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "messages": [{key: value for key, value in item.items() if key != "text"} for item in messages],
    }
    (REPORTS / f"{DAY}_对话导出核对.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in manifest.items()
                      if key not in ("messages", "source_files_snapshot")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
