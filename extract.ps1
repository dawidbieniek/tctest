param(
    [CmdletBinding()]
    [Parameter(Mandatory = $true)][string] $ChangesFilePath
)

# Constants
$cuIdRegex      = '(?i)CU-([A-Za-z0-9]+)'
$tasksListFile  = 'tasks.txt'

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

# Check for new tasks
$newTasks = Get-TaskIdsFromChanges
if ($newTasks.Length -gt 0) {
    Write-Host "Found $($newTasks.Length) new CU tasks:"
    $newTasks | ForEach-Object { Write-Host "- $_" }
} else {
    Write-Host "Couldn't find any new CU tasks"
    exit(0)
}

# Check for old tasks
if (Test-Path $tasksListFile) {
    $existingTasks = Get-Content $tasksListFile | Where-Object { $_.Trim() } 
    if ($existingTasks.Count -gt 0) {
        Write-Warning "Existing task list contains $($existingTasks.Count) tasks. This state is valid only when previous build failed or was stopped"
        Write-Host "Tasks in file:"
        $existingTasks | ForEach-Object { Write-Host "- $_" }
    }
} else {
    $existingTasks = @()
}

# Save tasks to file
$allTasks = $existingTasks + $newTasks | Select-Object -Unique

$allTasks | Out-File -FilePath $tasksListFile -Encoding UTF8
Write-Host "Written $($allTasks.Count) tasks to '${tasksListFile}':"
$allTasks | ForEach-Object { Write-Host "- $_" }