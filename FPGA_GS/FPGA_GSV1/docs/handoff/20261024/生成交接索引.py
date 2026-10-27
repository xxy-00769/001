"""只扫描本地文件元数据，输出可迁移索引；不构建、连接硬件或读取凭证内容。"""
import csv
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[2]
WORKSPACE = PROJECT.parent.parent
SKIP = {".git", "__pycache__", "node_modules", ".venv", ".venv312", ".venv404", ".venv405build"}
WHEN = datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")
stats = defaultdict(lambda: [0, 0])
docs = []
assets = []
errors = []


def scan(base, prefix):
    if not base.exists():
        errors.append(f"不存在：{prefix}")
        return
    for current, dirs, files in os.walk(base, onerror=lambda e: errors.append(str(e))):
        dirs[:] = [d for d in dirs if d not in SKIP and not d.startswith(".venv")]
        for name in files:
            path = Path(current) / name
            if path == Path(__file__).resolve() or OUT == path.parent:
                continue
            rel = path.relative_to(base)
            portable = prefix + "/" + rel.as_posix()
            try:
                info = path.stat()
            except OSError as exc:
                errors.append(f"{portable}: {exc}")
                continue
            bucket = prefix + "/" + (rel.parts[0] if len(rel.parts) > 1 else "[根文件]")
            stats[bucket][0] += 1
            stats[bucket][1] += info.st_size
            stamp = datetime.fromtimestamp(info.st_mtime, timezone(timedelta(hours=8))).isoformat(timespec="seconds")
            row = [portable, info.st_size, stamp]
            lower = name.lower()
            if path.suffix.lower() == ".md":
                docs.append(["Markdown原记录", *row])
            elif prefix == "${WORKSPACE}/资料" and path.suffix.lower() in {".pdf", ".csv"}:
                docs.append(["资料（仅建立路径索引）", *row])
            if prefix == "${PROJECT}" and rel.parts[0] == "release" and len(rel.parts) == 3 and path.suffix.lower() == ".sbit":
                assets.append(["发布位流；状态见对应README", *row])
            if prefix.endswith("/SC") and path.suffix.lower() in {".mp4", ".mkv", ".avi"}:
                assets.append(["原始视频；未重新散列", *row])
            if prefix == "${PROJECT}" and rel.parts[0] == "orangepi":
                if path.suffix.lower() in {".rknn", ".onnx", ".pt", ".ttf", ".ttc", ".whl"}:
                    assets.append(["模型/字体/依赖候选；是否生产用见manifest", *row])
                elif "manifest" in lower or lower.startswith("requirements") or rel.as_posix() == "orangepi/oneclick/config.json":
                    assets.append(["配置或来源清单；核对实际用途", *row])
            if path.suffix.lower() in {".lic", ".key", ".pem"} or lower in {"id_rsa", "id_ed25519"}:
                assets.append(["凭证/绑定授权候选；不读内容，不自动纳入通用包", *row])


scan(PROJECT, "${PROJECT}")
scan(PROJECT.parent / "SC", "${WORKSPACE}/FPGA_GS/SC")
scan(WORKSPACE / "资料", "${WORKSPACE}/资料")


def save(name, header, rows):
    with (OUT / name).open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(header)
        writer.writerows(rows)


save("资料与报告索引.tsv", ["分类", "可迁移相对位置", "字节数", "最后修改时间_UTC+08"], sorted(docs, key=lambda r: r[1]))
save("关键资产清单.tsv", ["用途提示", "可迁移相对位置", "字节数", "最后修改时间_UTC+08"], sorted(assets, key=lambda r: r[1]))
save("迁移目录统计.tsv", ["扫描目录", "已扫描文件数", "已扫描字节数", "GiB", "统计说明"],
     [[key, values[0], values[1], round(values[1] / (1024 ** 3), 3), "排除venv/git/cache；仅元数据扫描，不是冻结快照"] for key, values in sorted(stats.items())])
report = (
    f"扫描时间（北京时间）：{WHEN}\n"
    f"项目根：{PROJECT}\n"
    f"工作区根：{WORKSPACE}\n"
    f"文档索引：{len(docs)}条；关键资产：{len(assets)}条\n"
    f"元数据扫描文件数：{sum(v[0] for v in stats.values())}\n"
    f"元数据扫描总GiB：{sum(v[1] for v in stats.values()) / (1024 ** 3):.3f}\n"
    "排除：虚拟环境、Git内部文件、node_modules、__pycache__及本交接输出文件。\n"
    "未读取凭证内容、未计算全量源码/视频/模型哈希、未访问远端。\n"
    "扫描时开发可继续，修改时间不等于冻结版本；两端交付快照与既有manifest才是迁移校验依据。\n"
    "索引包含历史/失败/重复副本，不能按文件名或排序直接判定生产版本。\n"
    "资料目录中的安装包与绑定license须另按用途筛选；统计体积不等于推荐传输体积。\n"
    f"读取错误：{len(errors)}\n" + "\n".join(errors)
)
(OUT / "索引说明.txt").write_text(report, encoding="utf-8")
print(report)
