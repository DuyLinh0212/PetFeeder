param([ValidateSet('demo','mqtt','broker','test','build','app')][string]$Mode='demo')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$nodeCmd=Get-Command node -ErrorAction SilentlyContinue
if(-not $nodeCmd){throw 'Cần Node.js >=22.13 trong PATH.'}
if($Mode -eq 'build'){
  $pioPython=Join-Path $projectRoot 'work\pio-env\Scripts\python.exe'
  Push-Location (Join-Path $projectRoot 'PetFeeder')
  try {
    if(Test-Path -LiteralPath $pioPython){ & $pioPython -m platformio run }
    else { pio run }
  } finally { Pop-Location }
  exit $LASTEXITCODE
}
if($Mode -eq 'app'){
  $flutterCmd=Get-Command flutter -ErrorAction SilentlyContinue
  $flutterPath=if($flutterCmd){$flutterCmd.Source}else{'D:\a\testcode\flutter\bin\flutter.bat'}
  if(-not(Test-Path -LiteralPath $flutterPath)){throw 'Cần Flutter SDK. Xem README.md.'}
  Push-Location (Join-Path $projectRoot 'petfeeder_app')
  try { & $flutterPath pub get; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; & $flutterPath run -d edge --dart-define=API_URL=http://127.0.0.1:8080 }
  finally { Pop-Location }
  exit $LASTEXITCODE
}
Push-Location (Join-Path $projectRoot 'petfeeder_backend')
try {
  if(-not(Test-Path -LiteralPath 'node_modules\mqtt')){throw 'Thiếu dependencies. Chạy npm ci trong petfeeder_backend trước.'}
  switch($Mode){
    'demo' { & $nodeCmd.Source src/server.js --demo }
    'mqtt' { & $nodeCmd.Source src/server.js }
    'broker' { & $nodeCmd.Source src/broker.js }
    'test' { & $nodeCmd.Source --test 'test/*.test.js' }
  }
} finally { Pop-Location }
