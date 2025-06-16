param(
    [CmdletBinding()]
    [Parameter(Mandatory = $true)][string] $BuildNumber,
    [Parameter(Mandatory = $true)][string] $TcProjectName,
    [Parameter(Mandatory = $true)][string] $CuApiKey
)

# For tests
if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
    throw "Random failure occurred."
}

# Constants
$tasksListFile  = 'tasks.txt'

$projectAlreadyIsPresentWithoutBuildNrRegex = "(?i)\b{0}\b" # 0 - displayName
$projectAlreadyHasBuidNrRegex = "(?i)\b{0}\b\s*(?:[:\-]\s*|\s+)[0-9][A-Za-z0-9\.\-]*" # 0 - projectName

$getTaskUrl = "https://api.clickup.com/api/v2/task/{0}" # 0 - taskId
$getTaskHeaders = @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
}

$postFieldValueUrl = "https://api.clickup.com/api/v2/task/{0}/field/{1}" # 0 - taskId; 1 - fieldId
$postFieldValueHeaders = @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
    'Content-Type'  = 'application/json'
}

# Project name mapping
$projectNameMap = @{
    "Emplo"     = "TMS"
    "Admin2"    = "Admin"
    "??wallapi" = "Wall"
    "InnyProjekt" = "Nowy"
    "Tctest"    = "Stary"
}

function Get-TranslatedProjectName {
    param([string]$Name)

    if ($projectNameMap.ContainsKey($Name)) {
        Write-Host "Using '$($projectNameMap[$Name])' as project name"
        return $projectNameMap[$Name]
    }

    Write-Warning "Couldn't find '${Name}' in project name map"
    return $Name
}

function Get-TaskIdsFromFile {
    if (Test-Path $tasksListFile) {
        $existingTasks = Get-Content $tasksListFile | Where-Object { $_.Trim() } 
    } else {
        $existingTasks = @()
    }

    return $existingTasks
}

function Write-WebError {
    param(
        [Parameter(Mandatory)][System.Net.WebException] $Exception
    )

    $stream = $Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd()
    if ($responseBody) {
        $err = ($responseBody | ConvertFrom-Json)
        Write-Warning "[$TaskId] API error: $($err.err) (ECODE: $($err.ECODE))"
    }
    else {
        Write-Warning "[$TaskId] HTTP error: $($_.Exception.Message)"
    }
}

function Set-ClickUpFieldValue {
    param(
        [Parameter(Mandatory)][string] $TaskId,
        [Parameter(Mandatory)][string] $FieldId,
        [Parameter(Mandatory)][string] $Value
    )

    $body = @{ value = $Value } | ConvertTo-Json -Depth 2
    $url = $postFieldValueUrl -f $TaskId, $FieldId

    try {
        Invoke-RestMethod -Method Post -Uri $url -Headers $postFieldValueHeaders -Body $body
        Write-Host "[$TaskId] Successfully updated field to '$Value'`n"
        return $true
    }
    catch [System.Net.WebException] {
        Write-WebError -Exception $_.Exception
        return $false
    }
    catch {
        Write-Warning "[$TaskId] Unexpected error: $($_.Exception.Message)"
        return $false
    }
}

function Update-ClickUpTasks {
    param(
        [string[]] $TaskIds,
        [string] $ProjectName,
        [string] $BuildNumber
    )

    foreach ($taskId in $TaskIds) {
        $url = $getTaskUrl -f $taskId

        try {
            $response = Invoke-RestMethod -Method Get -Uri $url -Headers $getTaskHeaders
            $releaseField = $response.custom_fields | Where-Object { $_.name -eq "Release" }
            $releaseValue = if ($releaseField -and $releaseField.value) { $releaseField.value } else { "" }

            # Project present with build number
            if ($releaseValue -match ($projectAlreadyHasBuidNrRegex -f $ProjectName)) {
                $releaseValue = $releaseValue -replace ($projectAlreadyHasBuidNrRegex -f $ProjectName), "${ProjectName}: $BuildNumber"
            }
            # Project present without build number
            elseif ($releaseValue -match ($projectAlreadyIsPresentWithoutBuildNrRegex -f $ProjectName)) {
                $releaseValue = $releaseValue -replace ($projectAlreadyIsPresentWithoutBuildNrRegex -f $ProjectName), "${ProjectName}: $BuildNumber"
            }
            # Field is empty
            elseif ([string]::IsNullOrWhiteSpace($releaseValue)) {
                $releaseValue = "${ProjectName}: $BuildNumber"
            }
            # Field contains text
            else {
                $releaseValue = "${ProjectName}: $BuildNumber, $releaseValue"
            }

            Write-Host "[$taskId] changing Release field to '$releaseValue'"

            if (-not (Set-ClickUpFieldValue -TaskId $taskId -FieldId $releaseField.id -Value $releaseValue)) {
                Write-Warning "[$taskId] Failed to set Release field."
            }
        }
        catch [System.Net.WebException] {
            Write-WebError -Exception $_.Exception
            return $false
        }
        catch {
            Write-Warning "[$TaskId] Unexpected error: $($_.Exception.Message)"
            return $false
        }
    }
}

function Clear-TasksListFile {
    if (Test-Path $tasksListFile) {
        Remove-Item $tasksListFile -ErrorAction SilentlyContinue
        Write-Host "Removed '$tasksListFile'"
    } else {
        Write-Host "No '$tasksListFile' to clear"
    }
}

# Main Logic
$projectName = Get-TranslatedProjectName -Name $TcProjectName
$cuIds = Get-TaskIdsFromFile

if ($cuIds.Length -gt 0) {
    Write-Host "Found $($cuIds.Length) CU tasks:"
    $cuIds | ForEach-Object { Write-Host "- $_" }
    Write-Host
} else {
    Write-Host "Couldn't find any CU tasks"
    exit(0)
}

Update-ClickUpTasks -TaskIds $cuIds -ProjectName $projectName -BuildNumber $BuildNumber

Clear-TasksListFile