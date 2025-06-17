param(
    [CmdletBinding()]
    [Parameter(Mandatory)][string] $ChangesFilePath,
    [Parameter(Mandatory)][string] $BuildNumber,
    [Parameter(Mandatory)][string] $TcProjectName,
    [Parameter(Mandatory)][string] $CuApiKey,
    [Parameter(Mandatory)][string] $BranchName,
    [Parameter(Mandatory)][string] $TeamcityUrl,
    [Parameter(Mandatory)][string] $TcApiKey,
    [Parameter(Mandatory)][string] $BuildTypeId,
    [Parameter][bool] $Testing
)

# For tests
# throw "Random failure occurred."

# Regex
$cuIdRegex = '(?i)CU-([A-Za-z0-9]+)'
$projectAlreadyIsPresentWithoutBuildNrRegex = "(?i)\b{0}\b" # 0 - displayName
$projectAlreadyHasBuidNrRegex = "(?i)\b{0}\b\s*(?:[:\-]\s*|\s+)[0-9][A-Za-z0-9\.\-]*" # 0 - projectName

# Teamcity rest api
$tcHeaders = @{
  "Authorization" = "Bearer $TcApiKey"
}
$tcGetBuildsUrl  = "$TeamcityUrl/app/rest/builds?locator=buildType:$BuildTypeId,branch:$BranchName,state:finished,count:20&fields=build(id,status)"
$tcGetChangesUrl = "$TeamcityUrl/app/rest/changes?locator=build:(id:{0})&fields=change(version)" # 0 - buildId

# Clickup
$getTaskHeaders = @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
}
$getTaskUrl = "https://api.clickup.com/api/v2/task/{0}" # 0 - taskId

$postFieldValueHeaders = @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
    'Content-Type'  = 'application/json'
}
$postFieldValueUrl = "https://api.clickup.com/api/v2/task/{0}/field/{1}" # 0 - taskId; 1 - fieldId

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

function Get-PerviousBuildsRevs {
    $lastBuilds = Invoke-RestMethod -Method Get -Uri $tcGetBuildsUrl -Headers $tcHeaders

    $faliedBuildRevs = @()
    foreach ($build in $lastBuilds.builds.build) {
        if ($build.status -eq 'SUCCESS') { break }

        Write-Host "Found failed build: $($build.id)"

        $changes = Invoke-RestMethod -Method Get -Uri "$($tcGetChangesUrl -f $build.id)" -Headers $tcHeaders

        foreach ($change in $changes.changes.change.version) {
            $faliedBuildRevs += $change
        }
    }
    return $faliedBuildRevs | Select-Object -Unique
}

function Get-CurrentBuildRevs {
    $changedFiles = Get-Content $ChangesFilePath
    $revs = $changedFiles | ForEach-Object { ($_ -split ':')[-1] } 
    return $revs | Select-Object -Unique
}

function Get-TaskIdsFromRevs {
    param(
        [string[]] $Revs
    )
    if (-not $Revs -or $Revs.Count -eq 0) { return }

    $cuIds = @()
    foreach ($rev in $Revs) {
        if ([string]::IsNullOrWhiteSpace($rev)) { continue }

        $msg = git log -1 --format="%s" $rev
        $matchedIds = [regex]::Matches($msg, $cuIdRegex)
        foreach ($match in $matchedIds) {
            $cuIds += $match.Groups[1].Value
        }
    }

    return $cuIds | Select-Object -Unique
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
        Write-Host "[$TaskId] Successfully updated field to '$Value'"
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
                $releaseValue = $releaseValue -replace ($projectAlreadyHasBuidNrRegex -f $ProjectName), "${ProjectName}: 3.0.$BuildNumber"
            }
            # Project present without build number
            elseif ($releaseValue -match ($projectAlreadyIsPresentWithoutBuildNrRegex -f $ProjectName)) {
                $releaseValue = $releaseValue -replace ($projectAlreadyIsPresentWithoutBuildNrRegex -f $ProjectName), "${ProjectName}: 3.0.$BuildNumber"
            }
            # Field is empty
            elseif ([string]::IsNullOrWhiteSpace($releaseValue)) {
                $releaseValue = "${ProjectName}: 3.0.$BuildNumber"
            }
            # Field contains text
            else {
                $releaseValue = "${ProjectName}: 3.0.$BuildNumber, $releaseValue"
            }

            Write-Host "[$taskId] changing Release field to '$releaseValue'"

            if ($Testing -eq $true) { continue; }

            if (-not (Set-ClickUpFieldValue -TaskId $taskId -FieldId $releaseField.id -Value $releaseValue)) {
                Write-Warning "[$taskId] Failed to set Release field."
            }
        }
        catch [System.Net.WebException] {
            Write-WebError -Exception $_.Exception
        }
        catch {
            Write-Warning "[$TaskId] Unexpected error: $($_.Exception.Message)"
        }
    }
}

# Main Logic
$projectName = Get-TranslatedProjectName -Name $TcProjectName

$previousRevs = Get-PerviousBuildsRevs
$previousCuIds = Get-TaskIdsFromRevs -Revs $previousRevs
if ($previousCuIds.Count -gt 0) {
    Write-Warning "Found $($previousCuIds.Count) tasks in previous builds. This state is valid only when previous builds failed or were stopped"
    Write-Host "Previous builds tasks:"
    $previousCuIds | ForEach-Object { Write-Host "- $_" }
}

$currentRevs = Get-CurrentBuildRevs
$currentCuIds = Get-TaskIdsFromRevs -Revs $currentRevs
if ($currentCuIds.Count -gt 0) {
    Write-Host "Found new $($currentCuIds.Count) CU tasks:"
    $currentCuIds | ForEach-Object { Write-Host "- $_" }
}

if (-not $previousCuIds) { $previousCuIds = @() }
if (-not $currentCuIds) { $currentCuIds = @() }
$allCuIds = ($currentCuIds + $previousCuIds) | Select-Object -Unique

Update-ClickUpTasks -TaskIds $allCuIds -ProjectName $projectName -BuildNumber $BuildNumber