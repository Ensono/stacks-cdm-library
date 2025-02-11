
<#
    This is the entrypoint into the CDM check ADO integration which performs validation and sets common configuration.

    This script will invoke a custom PowerShell script for the ADO organisation, project and action
    Example: cdm_library/integrations/ado/[organisation name]/[project name]/CreateWorkitem.ps1
#>

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

# installing dependencies
$functions = (
   "Retry-Command.ps1",
   "Install-PowerShellModules.ps1" 
)

foreach ($function in $functions) {
    . ("{0}/powershell/functions/{1}" -f $env:CDM_LIBRARY_DIRECTORY, $function)
}


$script:adoDirectory = ("{0}/{1}/{2}/{3}" -f $env:CDM_INTEGRATIONS_DIRECTORY, "ado", $env:ADO_ORGANISATION_NAME, $env:ADO_PROJECT_NAME)

if (Test-Path -Path ("{0}/{1}.ps1" -f $adoDirectory, $env:ADO_ACTION)) {
    $script:adoActionFile = ("{0}/{1}.ps1" -f $adoDirectory, $env:ADO_ACTION)
} else {
    $script:adoActionFile = ("{0}/{1}/{2}.ps1" -f $env:CDM_LIBRARY_DIRECTORY, $adoDirectory, $env:ADO_ACTION)
}

$script:configurationFile = ("{0}/{1}" -f $adoDirectory , "configuration.yml")


if (Test-Path -Path $adoActionFile) {
    Write-Information -MessageData ("Running ADO action from '{0}'" -f $adoActionFile)
} else {
    throw ("ADO action filename '{0}' cannot be found" -f $adoActionFile)
}

if (Test-Path -Path $configurationFile) {
    Write-Information -MessageData ("Loading configuration from '{0}'`n" -f $configurationFile)
} else {
    throw ("Configuration filename '{0}' cannot be found" -f $configurationFile)
}

$parentConfiguration = @{
    checkName = $env:CHECK_NAME
    configurationFile = $configurationFile
    baseUrl = ("{0}/{1}/{2}" -f "https://dev.azure.com", $env:ADO_ORGANISATION_NAME, $env:ADO_PROJECT_NAME)
    clientName = $env:CLIENT_NAME
    accessToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($env:ADO_ACCESS_TOKEN)"))
    action = $env:ADO_ACTION
    stageDisplayName = $env:STAGE_DISPLAY_NAME
    checkDisplayName = $env:CHECK_DISPLAY_NAME
    jobId = $env:JOB_ID
    systemCollectionUri = ("{0}" -f $env:ADO_SYSTEM_COLLECTION_URI)
    systemProjectName = $env:ADO_SYSTEM_PROJECT_NAME
    buildId = $env:ADO_BUILD_ID
    buildNumber = $env:ADO_BUILD_NUMBER
}

& $adoActionFile
