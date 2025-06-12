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
$token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($env:system_teamcity_auth_userId):$($env:system_teamcity_auth_password)"))
foreach ($line in Get-Content $env:system_teamcity_build_changedFiles_file) {
  $rev = ($line -split ':')[-1]
  $req = [System.Net.HttpWebRequest]::Create("$env:teamcity_serverUrl/app/rest/changes/id:$rev")
  $req.Headers.Add("Authorization", "Basic $token")
  $xml = [xml]([System.IO.StreamReader]::new($req.GetResponse().GetResponseStream()).ReadToEnd())
  $comment = $xml.change.comment
  $user = $xml.change.commiter.vcsUsername
  Write-Host "Commit $rev by $user: $comment"
}
Write-Host "=== TeamCity Environment Information ==="
