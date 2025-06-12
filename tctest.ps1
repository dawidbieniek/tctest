param(
  [string]$changedFilesFile
)

Write-Host "=== TeamCity Environment Information ==="
$changedFile = $env:system_teamcity_build_changedFiles_file
$lines = Get-Content $changedFile
foreach ($line in $lines) {
  $parts = $line -split ':'
  $filePath = $parts[0]
  $changeType = $parts[1]
  $revision = $parts[2]
  Write-Host "File: $filePath, Change: $changeType, Revision: $revision"
}
Write-Host "=== #### ==="
$lines = Get-Content $changedFilesFile
foreach ($line in $lines) {
  $parts = $line -split ':'
  $filePath = $parts[0]
  $changeType = $parts[1]
  $revision = $parts[2]
  Write-Host "File: $filePath, Change: $changeType, Revision: $revision"
}
