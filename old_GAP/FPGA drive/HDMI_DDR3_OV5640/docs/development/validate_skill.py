"""Validate local rules and discovery without starting an agent or FPGA tools."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time

import yaml


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()


def discover(executable, cwds):
    proc = subprocess.Popen(
        [executable, "app-server", "--stdio"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    messages = queue.Queue()

    def read():
        for line in proc.stdout:
            messages.put(line)
        messages.put(None)

    threading.Thread(target=read, daemon=True).start()

    def send(method, params, ident=None):
        message = {"method": method, "params": params}
        if ident is not None:
            message["id"] = ident
        proc.stdin.write(json.dumps(message) + "\n")
        proc.stdin.flush()

    def receive(ident):
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            line = messages.get(timeout=max(0.01, deadline - time.monotonic()))
            if line is None:
                raise RuntimeError("App server closed before discovery response")
            message = json.loads(line)
            if message.get("id") == ident:
                if "error" in message:
                    raise RuntimeError(str(message["error"]))
                return message["result"]
        raise TimeoutError("App server discovery timed out")

    try:
        send("initialize", {"clientInfo": {
            "name": "project_skill_validation", "version": "1.0.0"}}, 1)
        receive(1)
        send("initialized", {})
        send("skills/list", {"cwds": [str(p) for p in cwds], "forceReload": True}, 2)
        result = receive(2)
        # Retain only this project's metadata, not unrelated personal skills.
        return [{"cwd": item["cwd"], "errors": item.get("errors", []),
                 "matches": [s for s in item["skills"]
                             if s["name"] == "mes50hp-development"]}
                for item in result["data"]]
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validator", required=True, type=Path)
    parser.add_argument("--codex", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Use a new evidence output; do not overwrite a prior run")
    repo = Path(__file__).resolve().parents[2]
    skill = repo / ".agents/skills/mes50hp-development"
    report = {"scope": "Static rules and real skills/list; no agent turn or FPGA operation",
              "checks": [], "limitations": ["Scenario review is manual, not model behavior testing"]}

    def check(name, ok, detail):
        report["checks"].append({"name": name, "passed": bool(ok), "detail": detail})

    env = dict(os.environ, PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1")
    validation = subprocess.run(
        [sys.executable, "-B", str(args.validator), str(skill)],
        capture_output=True, text=True, encoding="utf-8", env=env, check=False)
    check("skill_creator_quick_validate", validation.returncode == 0,
          (validation.stdout + validation.stderr).strip())
    content = (skill / "SKILL.md").read_text(encoding="utf-8")
    metadata = yaml.safe_load(content.split("---", 2)[1])
    policy = yaml.safe_load((skill / "agents/openai.yaml").read_text(encoding="utf-8"))
    check("name_and_implicit_policy", metadata["name"] == skill.name
          and policy["policy"]["allow_implicit_invocation"] is True, metadata)
    docs = [repo / "AGENTS.md", repo.parent / "AGENTS.md",
            repo / "docs/development/project_context.md",
            repo / "docs/development/skill_validation.md",
            *skill.rglob("*.md")]
    bad_links = []
    for doc in docs:
        for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", doc.read_text(encoding="utf-8")):
            if "://" not in target and not (doc.parent / target.split("#")[0]).exists():
                bad_links.append({"file": str(doc), "target": target})
    check("local_reference_targets", not bad_links, bad_links)
    before = json.loads((repo / "docs/development/validation/before.json").read_text(encoding="utf-8-sig"))
    changed = [item["path"] for item in before["files"]
               if not (repo / item["path"]).is_file()
               or sha256(repo / item["path"]) != item["sha256"]]
    git_env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, env=git_env, text=True).strip()
    index_path = subprocess.check_output(["git", "rev-parse", "--git-path", "index"],
                                         cwd=repo, env=git_env, text=True).strip()
    check("preexisting_files_unchanged", not changed, {
        "count": len(before["files"]), "changed": changed})
    check("head_index_unchanged", head == before["head"]
          and sha256(repo / index_path) == before["index_sha256"], {"head": head})
    try:
        discovery = discover(args.codex, [repo.parent, repo, repo / "source/rtl"])
        report["discovery"] = discovery
        check("actual_loader_discovery", len(discovery) == 3 and all(
            len(item["matches"]) == 1 and item["matches"][0].get("enabled") is True
            and not item["errors"] for item in discovery), "Entrance, Git root and RTL subdirectory")
    except (OSError, RuntimeError, TimeoutError, queue.Empty) as error:
        check("actual_loader_discovery", False, str(error))
    report["passed"] = all(item["passed"] for item in report["checks"])
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
