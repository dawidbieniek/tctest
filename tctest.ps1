Param(
  [string] [Parameter(Mandatory=$true)] $buildNumber,
  [string] [Parameter(Mandatory=$true)] $changesFile
)

Write-Host "=== Parameter values ==="
Write-Host "Build number: $buildNumber"
Write-Host "Changes file path: $changesFile"

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
foreach ($rev in $uniqueRevs) {
    $msg = git log -1 --pretty=format:"%H %an: %s" $rev
    Write-Host $msg
}
Write-Host "`n=== END ==="
