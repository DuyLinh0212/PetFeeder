param([string]$ApiBase='http://127.0.0.1:8082')
# Dot-source this file. It only defines manual request helpers; it runs no test and sends no feeding request on load.
$script:PetFeederManualBase=$ApiBase.TrimEnd('/')
$script:PetFeederManualRoot=Split-Path -Parent $PSScriptRoot
function PF-Get {
  param([ValidateSet('state','history','id')][string]$Path='state')
  Invoke-RestMethod -Uri "$script:PetFeederManualBase/api/$Path" -Method Get
}
function PF-Post {
  param([Parameter(Mandatory)][ValidateSet('feeding','config','schedules','demo')][string]$Path,
    [Parameter(Mandatory)]$Body)
  try {
    Invoke-RestMethod -Uri "$script:PetFeederManualBase/api/$Path" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($Body|ConvertTo-Json -Depth 20 -Compress)))
  } catch {
    if(-not $_.Exception.Response){throw}
    $response=$_.Exception.Response
    $raw=$_.ErrorDetails.Message
    if(-not $raw){$reader=New-Object IO.StreamReader($response.GetResponseStream());try{$raw=$reader.ReadToEnd()}finally{$reader.Dispose()}}
    try {$details=$raw|ConvertFrom-Json; [pscustomobject]@{http_status=[int]$response.StatusCode;error=$details.error;field=$details.field;message=$details.message}}
    catch {Write-Output $raw}
  }
}
function PF-NewCommand {
  param([double]$Grams=20,[int]$Ttl=60)
  $info=PF-Get id
  [pscustomobject]@{command_id=$info.command_id;source='APP';target_portion_g=$Grams;override=$false;created_at=[long]$info.now;expires_at=[long]$info.now+$Ttl}
}
function PF-Clock {
  $info=PF-Get id; $cfg=(PF-Get state).config
  [DateTimeOffset]::FromUnixTimeSeconds([long]$info.now).ToOffset([TimeSpan]::FromMinutes([double]$cfg.timezone_offset_min))
}
function PF-NewSchedule {
  param([int]$AfterMinutes=3,[double]$Grams=20,[string]$Id=('manual-'+[guid]::NewGuid().ToString('N')))
  $when=(PF-Clock).AddMinutes($AfterMinutes)
  [pscustomobject]@{schedule_id=$Id;hour=$when.Hour;minute=$when.Minute;days=@([int]$when.DayOfWeek);target_portion_g=$Grams;enabled=$true}
}
function PF-Mqtt {
  param([Parameter(Mandatory)][ValidateSet('command','event')][string]$Kind,
    [Parameter(Mandatory)]$Body,[ValidateRange(1,10)][int]$Repeat=1,[switch]$Retain)
  $nodeCommand=Get-Command node -ErrorAction Stop
  $publisher=Join-Path $script:PetFeederManualRoot 'petfeeder_backend\src\manualMqtt.js'
  $argsList=@($publisher,$Kind,"$Repeat")
  if($Retain){$argsList+='--retain'}
  $OutputEncoding=New-Object Text.UTF8Encoding
  $Body|ConvertTo-Json -Depth 20 -Compress | & $nodeCommand.Source @argsList
  if($LASTEXITCODE -ne 0){throw 'MQTT publish failed; check broker and DEVICE_ID.'}
}
