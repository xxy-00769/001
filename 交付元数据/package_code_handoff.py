"""Read-only source packaging; all generated files stay under transfer/."""
import csv
import hashlib
import io
import json
import os
import stat
import time
import zipfile
from datetime import datetime, timezone, timedelta
from pathlib import Path

BASE = Path(r'E:\zhoumian\FPGA')
STAMP = datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')
OUT = BASE / 'transfer' / ('代码工程交付_' + STAMP)
OUT.mkdir(parents=True, exist_ok=False)
SKIP_DIRS = {'.git', '.ssh', '.codex', '.agents', '__pycache__', 'node_modules', '.pytest_cache', '.mypy_cache', '.ruff_cache'}
STORED = {'.zip', '.rar', '.7z', '.gz', '.xz', '.zst', '.mp4', '.mkv', '.avi', '.mov', '.jpg', '.jpeg', '.png', '.webp', '.pdf', '.rknn', '.pt', '.pth', '.onnx', '.whl'}

def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()

def exclusion(p, directory=False):
    lo = p.name.lower()
    if p.is_symlink():
        return 'symlink_not_followed'
    if directory:
        if p.relative_to(BASE).as_posix().lower() == '资料/盘古50k开发板资料/pds开发软件安装包':
            return 'software_installers_not_in_code_package'
        if lo.startswith('.venv') or lo in SKIP_DIRS:
            return 'environment_cache_or_personal_state'
        if p.relative_to(BASE).as_posix().lower() == 'fpga_gs/fpga_gsv1/orangepi/oneclick/state':
            return 'runtime_pid_lock_and_control_state'
    else:
        if p.suffix.lower() in {'.pyc', '.pyo', '.pid', '.lock'}:
            return 'cache_or_runtime_lock'
        if p.suffix.lower() in {'.lic', '.pem', '.pfx', '.p12', '.key'} or lo in {'license.dat', 'credentials.json', 'secrets.json', 'token.txt', 'control_token', '.env'} or lo.startswith(('id_rsa', 'id_ed25519', '.env.')):
            return 'private_credential_or_host_license'
    return None

def scan(roots):
    selected = {}
    omitted = []
    for rel in roots:
        root = BASE / rel
        if not root.exists():
            omitted.append({'path': rel, 'reason': 'requested_root_missing'})
            continue
        if root.is_file():
            st = root.stat()
            selected[root.relative_to(BASE).as_posix()] = (st.st_size, st.st_mtime_ns)
            continue
        for d, dirs, files in os.walk(root, followlinks=False):
            kept = []
            for name in sorted(dirs):
                p = Path(d) / name
                reason = exclusion(p, True)
                if reason:
                    omitted.append({'path': p.relative_to(BASE).as_posix() + '/', 'reason': reason})
                else:
                    kept.append(name)
            dirs[:] = kept
            for name in sorted(files):
                p = Path(d) / name
                reason = exclusion(p)
                if reason:
                    omitted.append({'path': p.relative_to(BASE).as_posix(), 'reason': reason})
                    continue
                try:
                    st = p.stat()
                    if not stat.S_ISREG(st.st_mode):
                        raise OSError('not_regular_file')
                    selected[p.relative_to(BASE).as_posix()] = (st.st_size, st.st_mtime_ns)
                except OSError as e:
                    omitted.append({'path': p.relative_to(BASE).as_posix(), 'reason': str(e)})
    return selected, omitted

README = '''# 代码工程迁移包

这是代码和资料的实际副本，不是仅含交接文档的ZIP。两包均以原工作区为相对根，解压到同一个新目录（建议短路径，例如 D:/ADAS/），不要嵌套解压成两套目录。

## 包含范围

- 01：FPGA_GS/FPGA_GSV1 全部本地工程（包含 release、work、完整 build、vendor、rtl、约束、脚本、仿真、工具、模型、本地训练准备、报告、交接文档）和 FPGA_GS/SC 视频。
- 02：资料中的板卡和OV5640资料、比赛PDF及说明；old_GAP、JF、总目录docs/tools历史参考；tmp/v5_tools完整便携仿真工具及其包来源。
- 不带虚拟环境、Python缓存、node_modules、Git内部数据、个人代理状态、运行PID/锁/控制状态、明显私钥/凭据文件及主机绑定license。精确排除记录见 exclusions.json。保留开源LICENSE/NOTICE文本。
- 不包含PDS/ModelSim安装器或PDS主机授权；新电脑按交接要求合法安装和授权。不是整块E盘镜像。

## 解压后的入口

1. 先读 FPGA_GS/FPGA_GSV1/docs/handoff/20261024/先读我.md、项目总交接.md、FPGA完整开发交接.md、香橙派完整开发交接.md。
2. 三个新对话提示词在同目录 新电脑三个对话首条提示词.md；网页步骤在 另一台电脑网页版操作步骤.md。
3. 当前原曝光FPGA生产源码入口是 release/FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK/source/，构建入口 source/scripts/build_cam0.ps1。根RTL/README较旧；work/CAM0_motion 为已收尾的短曝光归档，不作为当前板上R0源码。
4. 香橙派部署根 /home/orangepi/fpga_gs_m401_v0_1_2_20261021，最近交接为 M4-06-r1；Windows一键入口位于 orangepi/oneclick/。IP最近为192.168.0.4，使用前按真实状态核对。
5. 本包只复制本地文件，没有SSH、启停服务、构建或下载位流。最后只读观察时Pi重启后服务未运行；不要把旧报告里的“正在运行”当实时状态。新旧电脑共用Pi时只指定一个服务控制负责人。

## 复现边界

- 香橙派完整远端备份尚未完成：部分ONNX、转换源码、中文字体、ARM系统环境仅在板端。本包保留本地已有的模型/视频及开发源码，不宣称可在空白新Pi完整恢复。详见香橙派完整开发交接及迁移资产映射.tsv。
- pc_traffic_20261024 是仍在推进的训练准备，不能据目录存在宣称训练结束或已有新权重部署；本包排除了 .venv-train。
- 为不中断开发采用逐文件读取，非全盘同一时刻快照。每文件SHA对应实际写入ZIP的字节；文件读取时的变化、打包期间新增/变动另列。最新冻结release优先于活跃work。不要回写此包覆盖仍在开发的源目录。
- metadata中的manifest.tsv逐项记录ZIP内容SHA/大小/读前读后状态；source_changes.json列打包期间变化；integrity.json为逐项CRC检查；外置SHA256SUMS用于核对ZIP传输。
- 现有文档/脚本可能包含旧电脑绝对路径，换盘符后仅在新副本调整；PDS、Python、PowerShell、驱动/串口号仍须按新机核对。没有执行新电脑独立恢复验收。
'''

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def make_archive(label, roots):
    started = now()
    files, excluded = scan(roots)
    total = sum(x[0] for x in files.values())
    print(json.dumps({'event':'start','package':label,'files':len(files),'source_GiB':round(total/2**30,3),'output':str(OUT)},ensure_ascii=False), flush=True)
    dest = OUT / (label + '.zip')
    meta = OUT / (label + '_metadata')
    meta.mkdir()
    records = []
    errors = []
    copied = 0
    tick = time.monotonic()
    with zipfile.ZipFile(dest, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as z:
        for i, (rel, initial) in enumerate(sorted(files.items()), 1):
            p = BASE / rel
            try:
                with p.open('rb') as src:
                    before = os.fstat(src.fileno())
                    zi = zipfile.ZipInfo(rel, time.localtime(before.st_mtime)[:6])
                    zi.external_attr = 0o100644 << 16
                    zi.compress_type = zipfile.ZIP_STORED if p.suffix.lower() in STORED else zipfile.ZIP_DEFLATED
                    zi._compresslevel = 1
                    h = hashlib.sha256()
                    size = 0
                    with z.open(zi, 'w', force_zip64=True) as target:
                        while True:
                            block = src.read(1024*1024)
                            if not block:
                                break
                            target.write(block)
                            h.update(block)
                            size += len(block)
                    after = os.fstat(src.fileno())
                stable = before.st_size == after.st_size == size and before.st_mtime_ns == after.st_mtime_ns
                records.append([rel, size, h.hexdigest(), before.st_size, before.st_mtime_ns, after.st_size, after.st_mtime_ns, stable, initial == (before.st_size, before.st_mtime_ns)])
                copied += size
            except OSError as e:
                errors.append({'path': rel, 'error': str(e)})
            if time.monotonic() - tick >= 10:
                print(json.dumps({'event':'copy_progress','package':label,'files':i,'total_files':len(files),'GiB':round(copied/2**30,2),'total_GiB':round(total/2**30,2)},ensure_ascii=False),flush=True)
                tick = time.monotonic()
        final, _ = scan(roots)
        changes = {
            'added_since_initial_scan': sorted(set(final)-set(files)),
            'deleted_since_initial_scan': sorted(set(files)-set(final)),
            'changed_since_initial_scan': [r for r in sorted(set(files)&set(final)) if files[r]!=final[r]],
            'unstable_while_reading': [r[0] for r in records if not r[7]],
            'read_errors': errors,
        }
        manifest = io.StringIO(newline='')
        w = csv.writer(manifest, delimiter='\t', lineterminator='\n')
        w.writerow(['path','archived_bytes','sha256','before_size','before_mtime_ns','after_size','after_mtime_ns','read_stable','same_as_initial_scan'])
        w.writerows(records)
        summary = {'package':label,'started':started,'copy_finished':now(),'roots':roots,'selected_files':len(files),'archived_source_files':len(records),'archived_source_bytes':copied,'excluded_entries':len(excluded),'source_changes':changes,'snapshot':'non_atomic_read_only_copy'}
        for name, content in [('manifest.tsv',manifest.getvalue()),('exclusions.json',json.dumps(excluded,ensure_ascii=False,indent=2)),('source_changes.json',json.dumps(changes,ensure_ascii=False,indent=2)),('summary.json',json.dumps(summary,ensure_ascii=False,indent=2))]:
            (meta/name).write_text(content,encoding='utf-8')
            z.writestr('交付元数据/'+label+'/'+name,content)
        z.writestr('代码工程迁移说明.md',README)
        z.write(Path(__file__), '交付元数据/package_code_handoff.py')
    print(json.dumps({'event':'archive_written','package':label,'archive_GiB':round(dest.stat().st_size/2**30,3),'changes':{k:len(v) for k,v in changes.items()}},ensure_ascii=False),flush=True)
    return dest, summary

main, main_summary = make_archive('01_代码工程与视频', ['FPGA_GS'])
extra_roots = ['资料/盘古50K开发板资料','资料/OV5640双目摄像头资料','old_GAP','JF','docs','tools','tmp/v5_tools']
extra_roots += [p.relative_to(BASE).as_posix() for p in sorted((BASE/'资料').iterdir()) if p.is_file() and p.suffix.lower() in {'.pdf','.txt','.md'}]
extra, extra_summary = make_archive('02_硬件资料与历史参考', extra_roots)
(OUT/'代码工程迁移说明.md').write_text(README,encoding='utf-8')
dump(OUT/'packaging_summary.json',{'created':now(),'packages':[main_summary,extra_summary]})
print(json.dumps({'event':'packages_ready_for_validation','directory':str(OUT)},ensure_ascii=False),flush=True)
