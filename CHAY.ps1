param([ValidateSet('backend','app','build','test')][string]$Mode='backend')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
function Require-Command([string]$Name) {
  $command=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $command){throw "Cần cài $Name và thêm vào PATH. Xem README.md."}
  return $command.Source
}
switch($Mode){
  'backend' {
    $runtime=Require-Command node
    Push-Location (Join-Path $projectRoot 'petfeeder_backend')
    try { & $runtime src/server.js } finally { Pop-Location }
  }
  'app' {
    $flutter=Get-Command flutter -ErrorAction SilentlyContinue
    $runtime=if($flutter){$flutter.Source}else{'D:\a\testcode\flutter\bin\flutter.bat'}
    if(-not(Test-Path -LiteralPath $runtime)){throw 'Cần Flutter SDK trong PATH.'}
    Push-Location (Join-Path $projectRoot 'petfeeder_app')
    try { & $runtime run -d chrome --dart-define=API_URL=http://127.0.0.1:3000 } finally { Pop-Location }
  }
  'build' {
    $pio=Get-Command pio -ErrorAction SilentlyContinue
    Push-Location (Join-Path $projectRoot 'PetFeeder')
    try {
      if($pio){ & $pio.Source run }
      elseif(Test-Path -LiteralPath 'D:\long2026\IOT\PetFeeder_Long\work\pio-env\Scripts\python.exe'){
        & 'D:\long2026\IOT\PetFeeder_Long\work\pio-env\Scripts\python.exe' -m platformio run
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
