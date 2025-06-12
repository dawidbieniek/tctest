param(
  [string]$changedFilesFile
)

Write-Host "=== TeamCity Environment Information ==="
$lines = Get-Content $changedFilesFile
foreach ($line in $lines) {
  $parts = $line -split ':'
  $filePath = $parts[0]
  $changeType = $parts[1]
  $revision = $parts[2]
  Write-Host "File: $filePath, Change: $changeType, Revision: $revision"
}
$uniqueRevs = $lines | ForEach-Object { ($_ -split ':')[-1] } | Sort-Object -Unique
foreach ($rev in $uniqueRevs) {
    $msg = git log -1 --pretty=format:"%H %an: %s" $rev
    Write-Host $msg
}
Write-Host "=== TeamCity Environment Information ==="
