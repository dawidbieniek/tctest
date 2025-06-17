param(
    [CmdletBinding()]
    [Parameter(Mandatory)][string] $ChangesFilePath,
    [Parameter(Mandatory)][string] $TeamcityUrl,
    [Parameter(Mandatory)][string] $BuildTypeId,
    [Parameter(Mandatory)][string] $BranchName
)

# Constants
$cuIdRegex      = '(?i)CU-([A-Za-z0-9]+)'
$tasksListFile  = 'tasks.txt'

$tcApiToken = "eyJ0eXAiOiAiVENWMiJ9.Q2o5SkR2WHJUOXQ3LUhRNm5Nd2hsNnkwWFlR.NTJkYTM5OTYtNDAxMy00MGQ1LTlkODYtZWY2MzRjMDVhMmQ5"

$headers = @{
  "Authorization" = "Bearer $tcApiToken"
}

$locator  = "buildType:$BuildTypeId,branch:$BranchName,state:finished,status:any,count:20"
$builds   = Invoke-RestMethod "$TeamcityUrl/app/rest/builds?locator=$locator" -Headers $headers
$aggregated = @()
foreach ($b in $builds.builds.build) {
  if ($b.status -eq 'SUCCESS') { break }
  $changesUrl = "$TeamcityUrl/app/rest/changes?locator=build:(id:$($b.id))&fields=change(files(file(name,changeType)))"
  $changes = Invoke-RestMethod $changesUrl -Headers $headers
  foreach ($c in $changes.change) {
    $aggregated += ,@{ file = $c.files.file.name; type = $c.files.file.changeType }
  }
}


function Get-TaskIdsFromLastBuild {
    $downloadUrl = "$TeamcityUrl/repository/download/$BuildTypeId/.lastFinished/${tasksListFile}?branch=$BranchName"
    
    try {
        $artifactResponse = Invoke-RestMethod -Uri $downloadUrl -Headers $headers;
    } 
    catch {
        if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
            return @()
        }
        else {
            throw $_.Exception
        }
    }

    if ($artifactResponse -is [string]) {
        $existingTasks = $artifactResponse -split "\r?\n" | Where-Object { $_.Trim() -ne "" }
    } elseif ($resp -is [string[]]) {
        $existingTasks = $artifactResponse | Where-Object { $_.Trim() -ne "" }
    } else {
        $existingTasks = ($artifactResponse.ToString()) -split "\r?\n" | Where-Object { $_.Trim() -ne "" }
    }

    if ($existingTasks.Count -gt 0) {
        Write-Warning "Existing task list contains $($existingTasks.Count) tasks. This state is valid only when previous build failed or was stopped"
        Write-Host "Tasks in file:"
        $existingTasks | ForEach-Object { Write-Host "- $_" }
    }

    return $existingTasks
}

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
$existingTasks = Get-TaskIdsFromLastBuild

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