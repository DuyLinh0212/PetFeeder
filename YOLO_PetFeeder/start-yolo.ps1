$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$taskPython = Join-Path $PSScriptRoot '.venv-yolo\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $taskPython)) {
    if(Get-Command py -ErrorAction SilentlyContinue){
        py -3.13 -m venv --system-site-packages .venv-yolo
    }else{
        python -m venv --system-site-packages .venv-yolo
    }
    if ($LASTEXITCODE -ne 0) { throw 'Could not create Python environment. Install Python 3.13 and try again.' }
}

& $taskPython -c "import importlib.util, sys; sys.exit(not all(importlib.util.find_spec(name) for name in ['ultralytics', 'fastapi', 'uvicorn', 'multipart', 'PIL']))"
if ($LASTEXITCODE -ne 0) {
    & $taskPython -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Check your Internet connection and try again.' }
}

Write-Host 'Open http://localhost:8002 after Application startup complete appears.'
& $taskPython (Join-Path $PSScriptRoot 'yolo_api.py')
