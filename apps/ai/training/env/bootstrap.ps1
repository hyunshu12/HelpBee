# apps/ai/training/env/bootstrap.ps1
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1   (재실행 안전)
$ErrorActionPreference = "Stop"
# 기본 정책(Restricted)은 .venv\Scripts\Activate.ps1 을 막는다.
# -ExecutionPolicy Bypass 로 실행 중이면 값은 기록되지만 ExecutionPolicyOverride 예외가 나므로 삼킨다.
try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force }
catch [System.Security.SecurityException] { }
winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements
winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
winget install -e --id 7zip.7zip --accept-package-agreements --accept-source-agreements
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("HELPBEE_DATA_ROOT", "D:\helpbee-data", "User")
New-Item -ItemType Directory -Force D:\helpbee-data | Out-Null
# 7-Zip 설치기는 PATH 를 건드리지 않는다 → tasks.py doctor / 압축 해제가 `7z` 를 찾도록 User PATH 에 추가
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*7-Zip*") {
    $newPath = if ($userPath) { "$($userPath.TrimEnd(';'));C:\Program Files\7-Zip" } else { "C:\Program Files\7-Zip" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}
# 새 셸에서:
#   cd <repo>\apps\ai
#   py -3.11 -m venv .venv ; .\.venv\Scripts\Activate.ps1
#   pip install torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu121
#   pip install -r requirements-gpu.txt
#   python tasks.py doctor      # cuda True NVIDIA GeForce RTX 4060 이어야 함
