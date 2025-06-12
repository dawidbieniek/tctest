Write-Host "=== TeamCity Environment Information ==="
# Expand these parameters using TeamCity's variable substitution
Write-Host "`n--- After Expansion ---"
Write-Host "Project Name: $env:TEAMCITY_PROJECT_NAME"
Write-Host "Build Configuration: $env:TEAMCITY_BUILDCONF_NAME"
Write-Host "Build Number: $env:BUILD_NUMBER"
Write-Host "Build ID: $env:TEAMCITY_BUILD_ID"
Write-Host "Agent Name: $env:TEAMCITY_AGENT_NAME"
Write-Host "Checkout Directory: $env:TEAMCITY_BUILD_CHECKOUTDIR"
$changedFilesFile = $env:system_teamcity_build_changedFiles_file
Write-Host "Changes: $changedFilesFile"
