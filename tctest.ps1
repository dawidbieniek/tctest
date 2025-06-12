Write-Host "=== TeamCity Environment Information ==="

# Display some TeamCity predefined parameters
Write-Host "Project Name: %teamcity.project.name%"
Write-Host "Build Configuration Name: %teamcity.buildConfName%"
Write-Host "Build Number: %build.number%"
Write-Host "Build ID: %teamcity.build.id%"
Write-Host "Agent Name: %teamcity.agent.name%"
Write-Host "Build Checkout Directory: %teamcity.build.checkoutDir%"
Write-Host "Changelog file: %system.teamcity.build.changedFiles.file%"


# Expand these parameters using TeamCity's variable substitution
Write-Host "`n--- After Expansion ---"
Write-Host "Project Name: $env:TEAMCITY_PROJECT_NAME"
Write-Host "Build Configuration: $env:TEAMCITY_BUILDCONF_NAME"
Write-Host "Build Number: $env:BUILD_NUMBER"
Write-Host "Build ID: $env:TEAMCITY_BUILD_ID"
Write-Host "Agent Name: $env:TEAMCITY_AGENT_NAME"
Write-Host "Checkout Directory: $env:TEAMCITY_BUILD_CHECKOUTDIR"
Write-Host "Changelog file: $env:SYSTEM_TEAMCITY_BUILD_CHANGEDFILES_FILE"
Write-Host "Changelog file (var): $(system.teamcity.build.changedFiles.file)"
Get-Content -Path $env:SYSTEM_TEAMCITY_BUILD_CHANGEDFILES_FILE
