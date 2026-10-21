param(
  [ValidateSet('run','build')][string]$Mode='run',
  [string]$ApiUrl='http://10.0.2.2:8080'
)
$ErrorActionPreference='Stop'
$flutterCmd=Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath=if($flutterCmd){$flutterCmd.Source}else{'D:\a\testcode\flutter\bin\flutter.bat'}
if(-not(Test-Path -LiteralPath $flutterPath)){throw 'Cần Flutter SDK trong PATH.'}
# This JDK fails to create a Unix-domain wakeup socket in the host's short-name TEMP.
# Use a process-local project temp directory; restore the environment when done.
$androidTemp=Join-Path $PSScriptRoot 'work\android-temp'
New-Item -ItemType Directory -Path $androidTemp -Force | Out-Null
$savedAndroidTemp=$env:TEMP; $savedAndroidTmp=$env:TMP
$env:TEMP=$androidTemp; $env:TMP=$androidTemp
Push-Location (Join-Path $PSScriptRoot 'petfeeder_app')
try {
  & $flutterPath pub get
  if($LASTEXITCODE -ne 0){throw 'flutter pub get chưa thành công.'}
  if($Mode -eq 'build'){
    & $flutterPath build apk --debug "--dart-define=API_URL=$ApiUrl"
    if($LASTEXITCODE -ne 0){throw 'Build APK chưa thành công; xem log phía trên.'}
    $apkFolder=Join-Path $PSScriptRoot 'apk'
    New-Item -ItemType Directory -Path $apkFolder -Force | Out-Null
    Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-debug.apk' -Destination (Join-Path $apkFolder 'PetFeeder-debug.apk')
    Write-Output "Đã tạo: $apkFolder\PetFeeder-debug.apk"
  } else {
    & $flutterPath run "--dart-define=API_URL=$ApiUrl"
    if($LASTEXITCODE -ne 0){throw 'Chưa chạy được app; cần chọn thiết bị Android.'}
  }
} finally {
  Pop-Location
  $env:TEMP=$savedAndroidTemp; $env:TMP=$savedAndroidTmp
}
