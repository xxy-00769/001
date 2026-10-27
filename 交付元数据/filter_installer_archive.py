"""Filter duplicate installation media from a transfer ZIP, preserving compressed entries."""
import copy
import csv
import io
import json
import os
import shutil
import sys
import zipfile
from pathlib import Path

folder = Path(sys.argv[1]).resolve()
archive = folder/'02_硬件资料与历史参考.zip'
temp = folder/'02_硬件资料与历史参考.filtered.zip'
prefix = '资料/盘古50K开发板资料/PDS开发软件安装包/'
label = archive.stem
meta = folder/(label+'_metadata')
with zipfile.ZipFile(archive) as src:
    manifest = list(csv.DictReader(io.StringIO((meta/'manifest.tsv').read_text(encoding='utf-8')),delimiter='\t'))
    removed = [row for row in manifest if row['path'].startswith(prefix)]
    kept = [row for row in manifest if not row['path'].startswith(prefix)]
    exclusions = json.loads((meta/'exclusions.json').read_text(encoding='utf-8'))
    exclusions.append({'path':prefix,'reason':'software_installers_not_in_code_package','files':len(removed),'bytes':sum(int(r['archived_bytes']) for r in removed)})
    summary = json.loads((meta/'summary.json').read_text(encoding='utf-8'))
    summary['initial_selected_before_filter'] = summary['selected_files']
    summary['selected_files'] = summary['archived_source_files'] = len(kept)
    summary['archived_source_bytes'] = sum(int(r['archived_bytes']) for r in kept)
    summary['excluded_entries'] = len(exclusions)
    summary['post_copy_filter'] = {'reason':'remove_duplicate_PDS_installers','files':len(removed),'bytes':sum(int(r['archived_bytes']) for r in removed)}
    table = io.StringIO(newline='')
    writer = csv.DictWriter(table, fieldnames=list(manifest[0]),delimiter='\t',lineterminator='\n')
    writer.writeheader()
    writer.writerows(kept)
    replacements = {
        'manifest.tsv':table.getvalue(),
        'exclusions.json':json.dumps(exclusions,ensure_ascii=False,indent=2),
        'summary.json':json.dumps(summary,ensure_ascii=False,indent=2),
    }
    skip = {'交付元数据/'+label+'/'+name for name in replacements}
    infos = sorted(src.infolist(),key=lambda x:x.header_offset)
    with zipfile.ZipFile(temp,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=1,allowZip64=True) as dest:
        for i, info in enumerate(infos):
            if info.filename.startswith(prefix) or info.filename in skip:
                continue
            end = infos[i+1].header_offset if i+1 < len(infos) else src.start_dir
            remaining = end-info.header_offset
            entry = copy.copy(info)
            entry.header_offset = dest.fp.tell()
            src.fp.seek(info.header_offset)
            while remaining:
                chunk = src.fp.read(min(4*1024*1024,remaining))
                if not chunk:
                    raise EOFError(info.filename)
                dest.fp.write(chunk)
                remaining -= len(chunk)
            dest.filelist.append(entry)
            dest.NameToInfo[entry.filename] = entry
            dest._didModify = True
            dest.start_dir = dest.fp.tell()
        for name,content in replacements.items():
            dest.writestr('交付元数据/'+label+'/'+name,content)
        dest.write(Path(__file__),'交付元数据/filter_installer_archive.py')
os.replace(temp,archive)
for name,content in replacements.items():
    (meta/name).write_text(content,encoding='utf-8')
overview = json.loads((folder/'packaging_summary.json').read_text(encoding='utf-8'))
overview['packages'] = [summary if x['package']==label else x for x in overview['packages']]
(folder/'packaging_summary.json').write_text(json.dumps(overview,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'filtered_files':len(removed),'removed_GiB':round(sum(int(r['archived_bytes']) for r in removed)/2**30,3),'final_archive_bytes':archive.stat().st_size,'remaining_source_files':len(kept)},ensure_ascii=False),flush=True)
