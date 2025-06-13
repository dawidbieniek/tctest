param(
  [string][Parameter(Mandatory)]$BuildNumber,
  [string][Parameter(Mandatory)]$ChangesFilePath,
  [string][Parameter(Mandatory)]$TcProjectName,
  [string][Parameter(Mandatory)]$CuApiKey
)

# patterns: {0} will be replaced with project display name
$hasBuildPattern    = '(?i)\b{0}\b\s*(?:[:\-]\s*|\s+)[0-9][A-Za-z0-9\.\-]*' # 0 - displayName
$plainNamePattern   = '(?i)\b{0}\b' # 0 - displayName
$cuIdPattern        = '(?i)CU-([A-Za-z0-9]+)'

$urlGetTaskTpl      = 'https://api.clickup.com/api/v2/task/{0}' # 0 - taskId
$urlSetFieldTpl     = 'https://api.clickup.com/api/v2/task/{0}/field/{1}' # 0 - taskId, 1 - fieldId

$projectMap = @{
  Emplo      = 'TMS'
  Admin2     = 'Admin'
  '??wallapi'= 'Wall'
  InnyProjekt= 'Nowy'
  Tctest     = 'Stary'
}

$displayName = $projectMap[$TcProjectName] ?: $TcProjectName

function Get-CuTaskIds {
  $revs = Get-Content $ChangesFilePath | ForEach-Object { ($_ -split ':')[-1] } | Select-Object -Unique
  $ids  = foreach($r in $revs){ git log -1 --format='%s' $r | ForEach-Object{ [regex]::Matches($_,$cuIdPattern) } }
  $ids | ForEach-Object{ $_.Groups[1].Value } | Select-Object -Unique
}

function Get-ReleaseInfo {
  param($task)
  $h=@{Authorization=$CuApiKey;Accept='application/json'}
  try {
    $resp = Invoke-RestMethod -Method Get -Uri ($urlGetTaskTpl -f $task) -Headers $h
    $fld  = $resp.custom_fields|Where name -eq 'Release'
    return [pscustomobject]@{Id=$fld.id;Value=($fld.value -or '')}
  } catch { return $null }
}

function Set-ReleaseValue {
  param($task,$fieldId,$value)
  $h=@{Authorization=$CuApiKey;Accept='application/json';'Content-Type'='application/json'}
  $b=@{value=$value}|ConvertTo-Json
  try {
    Invoke-RestMethod -Method Post -Uri ($urlSetFieldTpl -f $task,$fieldId) -Headers $h -Body $b
    Write-Host "[$task] → $value"
  } catch { Write-Warning "[$task] failed: $_" }
}

function Update-Value {
  param($cur,$name,$build)
  $has = ($hasBuildPattern -f $name)
  $pln = ($plainNamePattern -f $name)
  if($cur -match $has){ return $cur }
  if($cur -match $pln){ return $cur -replace $pln, "$name: $build" }
  $body = $cur.Trim('() ')
  return if(-not $body){ "$name: $build" } else { "$name: $build; $body" }
}

# main
$tasks = Get-CuTaskIds
$tasks|ForEach-Object{ Write-Host "Found: $_" }

foreach($t in $tasks){
  $info = Get-ReleaseInfo $t
  if(-not $info) { continue }
  $new = Update-Value $info.Value $displayName $BuildNumber
  if($new -ne $info.Value){
    Set-ReleaseValue $t $info.Id $new
  } else {
    Write-Host "[$t] up-to-date"
  }
}