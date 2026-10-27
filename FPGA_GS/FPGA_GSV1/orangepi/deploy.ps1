param(
    [string]$TargetHost = '192.168.0.4',
    [string]$TargetUser = 'orangepi',
    [int]$SshPort = 22,
    [string]$HostKeyAlias = '10.168.29.122',
    [string]$ReleaseName = 'fpga_gs_m401_v0_1_2_new_release'
)
$ErrorActionPreference = 'Stop'
if ($ReleaseName -notmatch '^fpga_gs_m401_[a-zA-Z0-9_-]+$') { throw 'Invalid dedicated release directory name' }
$SshArgs = @('-p', "$SshPort", '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes')
$ScpArgs = @('-P', "$SshPort", '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes')
if ($HostKeyAlias) {
    $SshArgs += @('-o', "HostKeyAlias=$HostKeyAlias")
    $ScpArgs += @('-o', "HostKeyAlias=$HostKeyAlias")
}
$Target = "$TargetUser@$TargetHost"
$Bundle = Join-Path $PSScriptRoot 'm401_v0.1.2_code.tar.gz'
$Files = @('main.py','playback.py','preview.html','vision.py','link.py','test_m401.py','test_web_preview.py','test_playback.py','simulate_peer.py','make_sample.py','make_native_sample.py',
    'serve_web_fixture.py','verify_web_browser.cjs','verify_web_running.cjs','verify_flow_browser.cjs','DELIVERY_v0.1.1.md','DELIVERY_v0.1.2.md',
    'requirements.txt','scene.example.json','scene.file_test.json','endpoints.contract.json','README.md','DELIVERY.md',
    'deploy.ps1','manifest.json','evidence','vendor')
& tar '--exclude=__pycache__' -czf $Bundle -C $PSScriptRoot @Files
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
# mkdir without -p intentionally refuses to overwrite an existing release.
& ssh @SshArgs $Target "umask 077; mkdir ~/$ReleaseName"
if ($LASTEXITCODE -ne 0) { throw 'New release directory creation failed; existing files preserved' }
& scp @ScpArgs $Bundle "${Target}:$ReleaseName/"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed' }
& ssh @SshArgs $Target "cd ~/$ReleaseName && tar -xzf m401_v0.1.2_code.tar.gz && python3 -m venv --without-pip --system-site-packages .venv && .venv/bin/python -c 'import cv2,numpy; print(cv2.__version__,numpy.__version__)' && .venv/bin/python -m unittest -v test_playback test_web_preview"
if ($LASTEXITCODE -ne 0) { throw 'Deployment check failed; inspect the dedicated directory (no system packages installed)' }
Write-Output "Deployed $Target`:~/$ReleaseName. Source/video and foreground startup: README.md"
