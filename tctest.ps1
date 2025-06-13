Param(
  [string] [Parameter(Mandatory=$true)] $buildNumber,
  [string] [Parameter(Mandatory=$true)] $changesFile
)

# Its for testing only
$cuApiKey = "pk_200656617_1O426MO22JSSR7YWVD4D9GL0XWX1PO78"
$headers = @{
    'Authorization' = $cuApiKey
    'Accept'        = 'application/json'
}

Write-Host "=== Parameter values ==="
Write-Host "Build number: $buildNumber"
Write-Host "Changes file path: $changesFile"
Write-Host "CU Api key: $cuApiKey"
Write-Host "Headers: $headers"

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
		Write-Host "---------------"
    } catch {
        Write-Warning "Failed to fetch task CU-$taskId $_"
    }
}

Write-Host "`n=== END ==="