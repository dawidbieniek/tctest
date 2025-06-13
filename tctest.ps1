Param(
  [string] [Parameter(Mandatory=$true)] $buildNumber,
  [string] [Parameter(Mandatory=$true)] $changesFile,
  [string] [Parameter(Mandatory=$true)] $projectName
)

# Its for testing only
$cuApiKey = "pk_200656617_1O426MO22JSSR7YWVD4D9GL0XWX1PO78"
$headers = @{
    'Authorization' = $cuApiKey
    'Accept'        = 'application/json'
    'Content-Type'  = 'application/json'
}
$projectMap = @{
    "InnyProjekt"   = "Nowy projekt"
    "Tctest"  = "Starszy projekt"
    "Takiej nazwy nie będzie"  = "SomethingElse"
}

Write-Host "=== Parameter values ==="
Write-Host "Build number: $buildNumber"
Write-Host "Changes file path: $changesFile"
Write-Host "Project name: $projectName"
Write-Host "CU Api key: $cuApiKey"
Write-Host "Headers: $headers"

$mappedName = $projectMap[$projectName]
if (-not $mappedName) {
	$mappedName = "Empty"
    Write-Warning "No mapping found for project '$projectName'"
}
else {
	Write-Host "Project name $mappedName"
}


$lines = Get-Content $changesFile
Write-Host "`n== Changes file contents: ==`n$($lines -join "`n")"

$uniqueRevs = $lines | ForEach-Object { ($_ -split ':')[-1] } | Sort-Object -Unique
Write-Host "`n== File Unique revs: ==`n$($uniqueRevs -join "`n")"

$commitMessages = @()
foreach ($rev in $uniqueRevs) {
    $msg = git log -1 --pretty=format:"%H %an: %s" $rev
    Write-Host $msg
	$commitMessages += $msg
}

$cuPattern = '(?i)CU-([A-Za-z0-9]+)'
$cuIds = @()
foreach ($msg in $commitMessages) {
    foreach ($match in [regex]::Matches($msg, $cuPattern)) {
		$cuIds += $match.Groups[1].Value
    }
}

$cuIds = $cuIds | Select-Object -Unique
Write-Host "== CU Ids ==`n$($cuIds -join "`n")"

Write-Host "`n`n=== Sending requests to CU API ==="
foreach ($taskId in $cuIds) {
    $url = "https://api.clickup.com/api/v2/task/$taskId"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
        Write-Host "Task $taskId retrieved successfully."
		Write-Host "Id: $($response.id)"
		Write-Host "Task: $($response.name)"
        Write-Host "Status: $($response.status.status)"
        Write-Host "Fields: $($response.custom_fields)"
		
		$releaseField = $response.custom_fields | Where-Object { $_.name -eq "Release" }
		$releaseValue = if ($releaseField -and $releaseField.value) { $releaseField.value } else { [string]::Empty }
		$fieldId = if ($releaseField -and $releaseField.id) { $releaseField.id } else { [string]::Empty }
        Write-Host "THE FIELD: $releaseField"
		Write-Host "---------------"
		
		$value = $mappedName + " " + $buildNumber
		Write-Host "Setting field value to: $value"
		$body = @{
			value = "$value"
		} | ConvertTo-Json -Depth 2
		
		try {
			$url = "https://api.clickup.com/api/v2/task/$taskId/field/$fieldId"
			Write-Host "Sending POST request"
			$response = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body
			Write-Host "Field updated successfully."
		} catch {
			Write-Warning "Failed to update field: $_"
		}
		
		
    } catch {
        Write-Warning "Failed to fetch task CU-$taskId $_"
    }
}

Write-Host "`n=== END ==="