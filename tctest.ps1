param(
  [string] [Parameter(Mandatory=$true)] $BuildNumber,
  [string] [Parameter(Mandatory=$true)] $ChangesFilePath,
  [string] [Parameter(Mandatory=$true)] $TcProjectName,
  [string] [Parameter(Mandatory=$true)] $CuApiKey
)

$apiKeyErrorCode = "OAUTH_019"
$projectAlreadyHasBuidNrRegex = "(?i)\b{0}\b\s*(?:[:\-]\s*|\s+)[0-9][A-Za-z0-9\.\-]*" # 0 - projectName
$projectAlreadyIsPresentWithoutBuildNrRegex = "(?i)\b{0}\b" # 0 - projectName

$cuIdRegex = '(?i)CU-([A-Za-z0-9]+)'
$getTaskUrl = "https://api.clickup.com/api/v2/task/{0}" # 0 - taskId
$getTaskHeaders = @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
}
$postFieldValueUrl = "https://api.clickup.com/api/v2/task/{0}/field/{1}" # 0 - taskId, 1 - fieldId
$postFieldValueHeaders= @{
    'Authorization' = $CuApiKey
    'Accept'        = 'application/json'
    'Content-Type'  = 'application/json'
}

# translate project name
$projectNameMap = @{
    "Emplo" = "TMS"
    "Admin2" = "Admin"
    "??wallapi" = "Wall"
	"InnyProjekt" = "Nowy"
	"Tctest" = "Stary"
}

$projectName = $projectNameMap[$TcProjectName]
if (-not $projectName) {
    Write-Warning "Couldn't find ${TcProjectName} in project name map"
	$projectName = $TcProjectName
}

# get task ids
## Get changes file contents
$changedFiles = Get-Content $ChangesFilePath
## Extract uniq revs
$uniqueRevs = $changedFiles | ForEach-Object { ($_ -split ':')[-1] } | Select-Object -Unique
## Get commit messages from revs
$commitMessages = $uniqueRevs | ForEach-Object { git log -1 --format="%s" $_ }
## Extract unique CU ids from messages
$cuIds = @()
foreach ($msg in $commitMessages) {
    $matches = [regex]::Matches($msg, $cuIdRegex)
    foreach ($match in $matches) {
        $cuIds += $match.Groups[1].Value
    }
}
$cuIds = $cuIds | Select-Object -Unique

Write-Host "Found CU task ids:"
$cuIds | ForEach-Object { Write-Host "- $_" }

# update tasks field
foreach ($taskId in $cuIds) {
    $url = $getTaskUrl -f taskId

    try {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $getTaskHeaders
		$releaseField = $response.custom_fields | Where-Object { $_.name -eq "Release" }
		$releaseValue = if ($releaseField -and $releaseField.value) { $releaseField.value } else { [string]::Empty }

		write-host $taskId
		# Check if build is already set
		if ($releaseValue -match ($projectAlreadyHasBuidNrRegex -f $projectName)) {
			write-host "Contains build nr $releaseValue"
			continue;
		}
		
		if ($releaseValue -match ($projectAlreadyIsPresentWithoutBuildNrRegex -f $projectName)) {
			write-host "Contains just project name $releaseValue"
			$releaseValue = $releaseValue -replace ($projectAlreadyIsPresentWithoutBuildNrRegex -f $projectName), "${projectName}: $BuildNumber"
		}
		elseif ([string]::IsNullOrWhiteSpace($releaseValue)) {
			write-host "Is empty $releaseValue"
			$releaseValue = "${projectName}: $BuildNumber"
		}
		else {
			write-host "Contains other things $releaseValue"
			$releaseValue = "${projectName}: $BuildNumber; " + $releaseValue
		}
		
		Write-Host "($taskId) changing Release field to '$releaseValue'"
		
		if (-not (ClickUpFieldValue -TaskId $taskId -FieldId $fieldId -Value $releaseValue)) {
			Write-Warning "[$taskId] Failed to set Release field."
		}
		
	}
	catch [System.Net.WebException] {        
		$errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errorResponseJson = $reader.ReadToEnd() | ConvertFrom-Json
		$errorCode = $errorResponseJson.ECODE
		if ($errorCode -eq $apiKeyErrorCode) {
			Write-Warning "Invalid ClickUp api key`n$_"
		}
		else {
			Write-Warning "Failed to fetch task: $taskId`n$_"
		}
	}
	catch {
		Write-Warning "Failed to fetch task: $taskId`n$_"
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
        Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body
        Write-Host "[$TaskId] ► Updated field $FieldId → $Value"
        return $true
    }
    catch [System.Net.WebException] {
        $stream = $_.Exception.Response.GetResponseStream()
        $responseBody = [System.IO.StreamReader]::new($stream).ReadToEnd()
        if ($responseBody) {
            $err = ($responseBody | ConvertFrom-Json)
            Write-Warning "[$TaskId] API error: $($err.err) (ECODE: $($err.ECODE))"
        }
        else {
            Write-Warning "[$TaskId] HTTP error: $($_.Exception.Message)"
        }
        return $false
    }
    catch {
        Write-Warning "[$TaskId] Unexpected error: $($_.Exception.Message)"
        return $false
    }
}