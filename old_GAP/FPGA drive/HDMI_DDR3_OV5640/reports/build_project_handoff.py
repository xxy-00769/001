"""Build a single handoff from visible chat messages and the curated overview."""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil

from export_daily_conversation import (
    LOCAL,
    THREAD,
    normalize_attachment_message,
    text_content,
    visible_user,
)


ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "reports"
DOCUMENT = REPORTS / "项目完整交接_2026-10-17.md"
MANIFEST = REPORTS / "项目交接核对_2026-10-17.json"
ASSETS = REPORTS / "handoff_assets"
MARKER = "<!-- BEGIN_GENERATED_HISTORY -->"
REQUEST = "整理所有对话内容和历史记录生成一个.md文档"
SUMMARY = re.compile(
    r"^(?:#{1,3}\s+|\*\*)(?:Active (?:Task|Goal|Request)|"
    r"Current (?:Task|Request)|Latest Request / Pending Reply)(?:\b|[ *])"
)
SECRET_PATTERNS = [
    re.compile(
        r"-----BEGIN (?:[A-Z0-9 ]* )?PRIVATE KEY-----.*?"
        r"-----END (?:[A-Z0-9 ]* )?PRIVATE KEY-----",
        re.DOTALL,
    ),
    re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\bhf_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bAIza[A-Za-z0-9_-]{30,}\b"),
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
]
SECRET_ASSIGNMENT = re.compile(
    r"(?i)(\b(?:OPENAI_API_KEY|HF_TOKEN|GITHUB_TOKEN|GH_TOKEN|"
    r"api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|"
    r"password|passwd|secret[_-]?key)\b[\"']?\s*[:=]\s*[\"']?)"
    r"([A-Za-z0-9_+=/.-]{12,})"
)
URL_AUTH = re.compile(r"(?i)(https?://)[^/\s:@]+:[^/\s@]+@")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def redact(text):
    count = 0
    for pattern in SECRET_PATTERNS:
        text, matched = pattern.subn("[REDACTED_CREDENTIAL]", text)
        count += matched
    text, matched = SECRET_ASSIGNMENT.subn(r"\1[REDACTED_CREDENTIAL]", text)
    count += matched
    text, matched = URL_AUTH.subn(r"\1[REDACTED_CREDENTIAL]@", text)
    return text, count + matched


def attachment_paths(text):
    paths = re.findall(r"^## .+?: ([A-Za-z]:[^\r\n]+)$", text, re.MULTILINE)
    paths += re.findall(r'<image name=\[Image #\d+\] path="([^"]+)">', text)
    return [
        Path(path.replace("\\", "/"))
        for path in paths
        if Path(path).suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".pdf"}
    ]


def collect():
    paths = sorted((Path.home() / ".codex/sessions").rglob(f"*{THREAD}*.jsonl"))
    if not paths:
        raise RuntimeError("No saved session logs for this conversation")
    messages = {}
    exclusions = []
    sources = []
    for path in paths:
        sources.append({"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size})
        with path.open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                row = json.loads(line)
                item = row.get("payload", {})
                if row.get("type") != "response_item" or item.get("type") != "message":
                    continue
                role = item.get("role")
                if role not in {"user", "assistant"}:
                    continue
                stamp = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
                stamp = stamp.astimezone(LOCAL).isoformat()
                phase = item.get("phase")
                text, images = text_content(item.get("content", []))
                reason = None
                if role == "assistant" and phase not in {"commentary", "final_answer", "final"}:
                    reason = "nonvisible_assistant_channel"
                elif role == "assistant" and SUMMARY.match(text):
                    reason = "context_handoff_summary"
                elif role == "user" and not visible_user(text):
                    reason = "injected_context"
                elif not text and not images:
                    reason = "empty_message"
                if reason:
                    exclusions.append((stamp, reason))
                    continue
                key = item.get("id") or (stamp, role, phase, text)
                if key in messages:
                    exclusions.append((stamp, "replayed_message"))
                    continue
                messages[key] = {
                    "id": item.get("id"),
                    "timestamp": stamp,
                    "role": role,
                    "phase": phase,
                    "text": normalize_attachment_message(text, images) if role == "user" else text,
                    "attachments": [str(p) for p in attachment_paths(text)] if role == "user" else [],
                    "source": str(path),
                    "source_line": line_number,
                }
    ordered = sorted(messages.values(), key=lambda item: item["timestamp"])
    cutoffs = [m["timestamp"] for m in ordered if m["role"] == "user" and REQUEST in m["text"]]
    if not cutoffs:
        raise RuntimeError("The user's handoff request was not found")
    cutoff = min(cutoffs)
    ordered = [m for m in ordered if m["timestamp"] <= cutoff]
    excluded = Counter(reason for stamp, reason in exclusions if stamp <= cutoff)
    return ordered, sources, dict(excluded), cutoff


def archive_attachments(messages):
    unique = {}
    for message in messages:
        for source in message["attachments"]:
            unique.setdefault(source.lower(), source)
    ASSETS.mkdir(exist_ok=True)
    inventory = []
    for source in unique.values():
        path = Path(source)
        entry = {"original": str(path), "exists_at_export": path.is_file()}
        if path.is_file():
            digest = sha256(path)
            target = ASSETS / f"{digest[:12]}_{path.name}"
            if target.exists():
                if sha256(target) != digest:
                    raise RuntimeError(f"Conflicting attachment archive: {target.name}")
            else:
                shutil.copyfile(path, target)
            entry.update({"archived": str(target), "sha256": digest, "bytes": path.stat().st_size})
        inventory.append(entry)
    return inventory


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    messages, sources, excluded, cutoff = collect()
    counts = Counter("user" if m["role"] == "user" else m["phase"] for m in messages)
    days = Counter(m["timestamp"][:10] for m in messages)
    brief = {
        "messages": len(messages), "counts": dict(counts), "by_day": dict(days),
        "first": messages[0]["timestamp"], "cutoff": cutoff, "source_files": len(sources),
        "excluded": excluded,
    }
    if args.inspect:
        print(json.dumps(brief, ensure_ascii=False, indent=2))
        return
    overview = DOCUMENT.read_text(encoding="utf-8").split(MARKER, 1)[0].rstrip()
    for label, value in {
        "{{MESSAGE_COUNT}}": len(messages),
        "{{USER_COUNT}}": counts["user"],
        "{{COMMENTARY_COUNT}}": counts["commentary"],
        "{{FINAL_COUNT}}": counts["final"] + counts["final_answer"],
        "{{FIRST_MESSAGE}}": messages[0]["timestamp"],
        "{{CUTOFF}}": cutoff,
    }.items():
        overview = overview.replace(label, str(value))
    inventory = archive_attachments(messages)
    archive_map = {entry["original"].lower(): entry.get("archived") for entry in inventory}
    blocks = [overview, "", MARKER, "", "## 附录 A：本聊天完整可见对话", "",
              "以下逐条记录保留当时原话，不代表其中的历史判断仍然正确，也不构成现在重新烧录、采购或读取密钥的授权。"
              "有冲突时以本交接正文的最新状态和当前文件核查为准。", "",
              "已排除内部推理、上下文交接摘要、系统/开发者指令与工具原始交互；附件以路径和本地归档代替内嵌编码。", ""]
    redactions = 0
    for number, message in enumerate(messages, 1):
        role = "用户" if message["role"] == "user" else (
            "助手进度说明" if message["phase"] == "commentary" else "助手正式答复")
        text, matched = redact(message["text"])
        redactions += matched
        blocks.extend([
            f"### H{number:04d} | {message['timestamp']} | {role}", "", text, "",
        ])
        for source in message["attachments"]:
            target = archive_map.get(source.lower())
            if target:
                blocks.extend([f"归档附件：[{Path(target).name}](/{Path(target).as_posix()})", ""])
        blocks.extend(["---", ""])
    blocks.extend(["## 附录 B：用户附件归档清单", "",
                   "只归档本聊天中用户明确发送的图片和赛题 PDF；不复制任何认证文件或工具许可证。"
                   "临时附件不存在时如实标为缺失，不臆造图像内容。", "",
                   "| 原始文件 | 现有本地归档 | SHA256 |", "| --- | --- | --- |"])
    for entry in inventory:
        target = entry.get("archived")
        destination = f"[本地归档](/{Path(target).as_posix()})" if target else "缺失，未归档"
        blocks.append(f"| `{entry['original']}` | {destination} | `{entry.get('sha256', '-')}` |")
    daily = REPORTS / "2026-10-17_工作复盘.md"
    daily_text, matched = redact(daily.read_text(encoding="utf-8"))
    redactions += matched
    blocks.extend(["", "## 附录 C：先前每日工作复盘原文", "",
                   "这份日报截至 2026-10-17 20:05 的整理请求，作为历史快照保留；"
                   "其中“今天”“本次”的含义属于当时，不等于新对话当前操作。", "",
                   daily_text, "", "<!-- END_GENERATED_HISTORY -->", ""])
    DOCUMENT.write_text("\n".join(blocks), encoding="utf-8")
    manifest = {
        **brief,
        "message_count": len(messages),
        "thread_id": THREAD,
        "timezone": "+08:00",
        "source_files_snapshot": sources,
        "attachments": inventory,
        "credential_redactions": redactions,
        "output": str(DOCUMENT),
        "output_sha256": sha256(DOCUMENT),
        "daily_review_sha256": sha256(daily),
        "messages": [
            {key: value for key, value in message.items() if key != "text"}
            for message in messages
        ],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        **brief,
        "attachments_archived": sum("archived" in entry for entry in inventory),
        "attachments_missing": sum("archived" not in entry for entry in inventory),
        "credential_redactions": redactions,
        "output": str(DOCUMENT),
        "output_bytes": DOCUMENT.stat().st_size,
        "output_sha256": manifest["output_sha256"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
