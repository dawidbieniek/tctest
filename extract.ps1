param(
    [CmdletBinding()]
    [Parameter(Mandatory = $true)][string] $ChangesFilePath,
    [Parameter(Mandatory)][string] $BranchName
)

# Constants
$cuIdRegex      = '(?i)CU-([A-Za-z0-9]+)'
$tasksListFile  = 'tasks.txt'

$tcApiToken = "eyJ0eXAiOiAiVENWMiJ9.Q2o5SkR2WHJUOXQ3LUhRNm5Nd2hsNnkwWFlR.NTJkYTM5OTYtNDAxMy00MGQ1LTlkODYtZWY2MzRjMDVhMmQ5"

$teamcityUrl     = "http://teamcity-server:8111"
$buildTypeId     = "Tctest_Build"

$headers = @{
  "Authorization" = "Bearer $tcApiToken"
}

$downloadUrl = "$teamcityUrl/repository/download/$buildTypeId/.lastFinished/${tasksListFile}?branch=$BranchName"
$resp = Invoke-RestMethod -Uri $downloadUrl -Headers $headers;
Write-Host $resp


function Get-TaskIdsFromChanges {
    $changedFiles = Get-Content $ChangesFilePath
    $uniqueRevs = $changedFiles | ForEach-Object { ($_ -split ':')[-1] } | Select-Object -Unique
    $commitMessages = $uniqueRevs | ForEach-Object { git log -1 --format="%s" $_ }

    $cuIds = @()
    foreach ($msg in $commitMessages) {
        $matchedIds = [regex]::Matches($msg, $cuIdRegex)
        foreach ($match in $matchedIds) {
            $cuIds += $match.Groups[1].Value
        }
    }

    return $cuIds | Select-Object -Unique
}

# Check for old tasks
# if (Test-Path $tasksListFile) {
#     $existingTasks = Get-Content $tasksListFile | Where-Object { $_.Trim() } 
#     if ($existingTasks.Count -gt 0) {
#         Write-Warning "Existing task list contains $($existingTasks.Count) tasks. This state is valid only when previous build failed or was stopped"
#         Write-Host "Tasks in file:"
#         $existingTasks | ForEach-Object { Write-Host "- $_" }
#     }
# } else {
#     $existingTasks = @()
# }
if ($resp -is [string]) {
    # Split by Windows or Unix line endings
    $existingTasks = $resp -split "\r?\n" | Where-Object { $_.Trim() -ne "" }
} elseif ($resp -is [string[]]) {
    # Already an array
    $existingTasks = $resp | Where-Object { $_.Trim() -ne "" }
} else {
    # Fallback: convert to string and split
    $existingTasks = ($resp.ToString()) -split "\r?\n" | Where-Object { $_.Trim() -ne "" }
}

Write-Host $existingTasks

# Check for new tasks
$newTasks = Get-TaskIdsFromChanges
if ($newTasks.Length -gt 0) {
    Write-Host "Found $($newTasks.Length) new CU tasks:"
    $newTasks | ForEach-Object { Write-Host "- $_" }
} else {
    Write-Host "Couldn't find any new CU tasks"
    exit(0)
}

# Save tasks to file
$allTasks = $existingTasks + $newTasks | Select-Object -Unique

$allTasks | Out-File -FilePath $tasksListFile -Encoding UTF8
Write-Host "Saved $($allTasks.Count) tasks to '${tasksListFile}':"
$allTasks | ForEach-Object { Write-Host "- $_" }