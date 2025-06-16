param(
    [CmdletBinding()]
    [Parameter(Mandatory = $true)][string] $ChangesFilePath
)


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

$tasks = Get-TaskIdsFromChanges
$outFile = "$Env:TEAMCITY_BUILD_CHECKOUTDIR\tasks.txt"
$tasks | Out-File -FilePath $outFile -Encoding UTF8

Write-Host "Saved $($tasks.Count) tasks to tasks.txt"