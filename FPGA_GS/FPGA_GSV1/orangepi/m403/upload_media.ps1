param([string]$Source=(Join-Path $PSScriptRoot '../../../SC'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$cfg=Get-Content (Join-Path $root 'oneclick/config.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($cfg.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$'){throw '远端目录格式无效'}
$rows=Get-Content (Join-Path $PSScriptRoot 'media_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($r in $rows){$p=Join-Path $Source $r.name;if((Get-Item $p).Length -ne $r.bytes -or (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() -ne $r.sha256){throw "本机原片与清单不同：$p"}}
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($rows|ConvertTo-Json -Compress)))
$target="$($cfg.ssh_user)@$($cfg.ssh_host)";$argsSsh=@('-p',[string]$cfg.ssh_port,'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Inspect {
 $raw=& ssh @argsSsh $target "cd '$($cfg.remote_dir)' && .venv/bin/python m403/media_transfer.py inspect --manifest $b64"
 if($LASTEXITCODE){throw 'SSH素材校验失败'};return ($raw|ConvertFrom-Json)
}
$before=Inspect;$missing=@($rows|Where-Object {$r=$_;$match=$before.files|Where-Object {$_.name -eq $r.name};$match.sha256 -ne $r.sha256 -or $match.bytes -ne $r.bytes})
$needed=($missing|Measure-Object -Property bytes -Sum).Sum
if($before.free_bytes -lt ($needed+256MB)){throw '香橙派磁盘空间不足，未上传'}
$actions=@()
foreach($r in $rows){
 if($r.name -notin $missing.name){Write-Host "SHA256一致，跳过：$($r.name)";$actions+=@{name=$r.name;action='SKIP_MATCHING_SHA256'};continue}
 Write-Host "上传原片：$($r.name)"
 & scp -P $cfg.ssh_port -o StrictHostKeyChecking=yes (Join-Path $Source $r.name) "${target}:$($cfg.remote_dir)/media/.$($r.name).m403_upload"
 if($LASTEXITCODE){throw 'SCP失败，保留原片和临时文件'}
 $raw=& ssh @argsSsh $target "cd '$($cfg.remote_dir)' && .venv/bin/python m403/media_transfer.py commit --manifest $b64 --name $($r.name)"
 if($LASTEXITCODE){throw 'SHA256提交失败，未覆盖原片'};$actions+=($raw|ConvertFrom-Json)
}
$after=Inspect
foreach($r in $rows){$f=$after.files|Where-Object {$_.name -eq $r.name};if($f.sha256 -ne $r.sha256 -or $f.bytes -ne $r.bytes){throw "最终核验失败：$($r.name)"}}
$report=Join-Path $PSScriptRoot ('evidence/upload_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.json')
[IO.File]::WriteAllText($report,(@{verified=$after;before=$before;actions=$actions;source=(Resolve-Path $Source).Path}|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false));Write-Host "四原片大小和SHA256核验完成：$report"
