Param(
  [string] [Parameter(Mandatory=$true)] $buildNumber,
  [string] [Parameter(Mandatory=$true)] $changesFile
)

# Its for testing only
$cuApiKey = "pk_200656617_1O426MO22JSSR7YWVD4D9GL0XWX1PO78"

Write-Host "=== Parameter values ==="
Write-Host "Build number: $buildNumber"
Write-Host "Changes file path: $changesFile"
Write-Host "CU Api key: $cuApiKey"

Write-Host "`n== Changes file contents: =="
$lines = Get-Content $changesFile
foreach ($line in $lines) {
  Write-Host $line
  #$parts = $line -split ':'
  #$filePath = $parts[0]
  #$changeType = $parts[1]
  #$revision = $parts[2]
  #Write-Host "File: $filePath, Change: $changeType, Revision: $revision"
}

Write-Host "`n== File Unique revs: =="
$uniqueRevs = $lines | ForEach-Object { ($_ -split ':')[-1] } | Sort-Object -Unique
$commitMessages = @()
foreach ($rev in $uniqueRevs) {
    $msg = git log -1 --pretty=format:"%H %an: %s" $rev
    Write-Host $msg
	$commitMessages += $msg
}

$cuPattern = '(?i)\[CU-[A-Za-z0-9]+\]'
$cuIds = @()

foreach ($msg in $commitMessages) {
    foreach ($match in [regex]::Matches($msg, $cuPattern)) {
        $id = $match.Value.Trim('[', ']')
        $cuIds += $id
    }
}

Write-Host "== CU Ids ==`n$($cuIds -join "`n")"

$uniqueIds = $cuIds | Select-Object -Unique
Write-Host "== Unique CU Ids ==`n$($uniqueIds -join "`n")"

Write-Host "`n=== END ==="