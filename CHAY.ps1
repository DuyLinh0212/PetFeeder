param([ValidateSet('backend','app','build','test','yolo')][string]$Mode='backend')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
function Require-Command([string]$Name) {
  $command=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $command){throw "Cần cài $Name và thêm vào PATH. Xem README.md."}
  return $command.Source
}
switch($Mode){
  'yolo' {
    $python=Join-Path $projectRoot 'work\yolo-env\Scripts\python.exe'
    if(Test-Path -LiteralPath $python){
      & $python (Join-Path $projectRoot 'YOLO_PetFeeder\yolo_api.py')
    } else {
      & (Join-Path $projectRoot 'YOLO_PetFeeder\start-yolo.ps1')
    }
  }
  'backend' {
    $runtime=Require-Command node
    Push-Location (Join-Path $projectRoot 'petfeeder_backend')
    try { & $runtime src/server.js } finally { Pop-Location }
  }
  'app' {
    $runtime=Require-Command flutter
    Push-Location (Join-Path $projectRoot 'petfeeder_app')
    try { & $runtime run -d chrome --dart-define=API_URL=http://127.0.0.1:3000 } finally { Pop-Location }
  }
  'build' {
    $pio=Get-Command pio -ErrorAction SilentlyContinue
    Push-Location (Join-Path $projectRoot 'PetFeeder')
    try {
      if($pio){ & $pio.Source run }
      elseif(Get-Command platformio -ErrorAction SilentlyContinue){ & (Require-Command platformio) run }
      elseif(Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.platformio\penv\Scripts\platformio.exe')){
        & (Join-Path $env:USERPROFILE '.platformio\penv\Scripts\platformio.exe') run
      }else {throw 'Cần cài PlatformIO Core.'}
    } finally { Pop-Location }
  }
  'test' {
    $runtime=Require-Command node
    Push-Location (Join-Path $projectRoot 'petfeeder_backend')
    try { & $runtime --test 'test/*.test.mjs' } finally { Pop-Location }
  }
}
exit $LASTEXITCODE
