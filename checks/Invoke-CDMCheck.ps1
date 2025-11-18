<#
    This is the entrypoint into a CDM check which performs common validation and sets common configuration.

    This script will invoke a custom PowerShell script for the check
    Example: checks/terraform/check.ps1
#>

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

# dot-sourcing functions
$functions = (
   "Retry-Command.ps1",
   "Install-PowerShellModules.ps1" 
)

foreach ($function in $functions) {
    . ("{0}/powershell/functions/{1}" -f $env:CDM_LIBRARY_DIRECTORY, $function)
}

# time format and zones
$script:targetTimeZone = Get-TimeZone -ListAvailable | Where-Object {$_.id -eq $env:CDM_DATE_TIMEZONE}
$script:dateTime = [System.TimeZoneInfo]::ConvertTime($([datetime]::ParseExact($(Get-Date -Format $env:CDM_DATE_FORMAT), $env:CDM_DATE_FORMAT, $null).ToUniversalTime()), $targetTimeZone)
$script:skipUntilDateTime = [datetime]::ParseExact($env:SKIP_UNTIL, $env:CDM_DATE_FORMAT, $null)

Write-Information -MessageData ("Date: {0} {1}`n" -f $dateTime.ToString($env:CDM_DATE_FORMAT), $targetTimeZone.DisplayName)

# defining runtime paths
$script:checkDirectory = ("{0}/{1}" -f $env:CDM_CHECKS_DIRECTORY, $env:CHECK_NAME)

# check file
$script:checkFile = ("{0}/{1}" -f $checkDirectory, "check.ps1")

# aws authentication environment variables
$script:awsAccessKeyId = $env:AWS_ACCESS_KEY_ID
$script:awsSecretAccessKey = $env:AWS_SECRET_ACCESS_KEY
$script:envAwsKeyId = $env:ENV_AWS_KEY_ID
$script:envAwsSecretAccessKey = $env:ENV_AWS_SECRET_ACCESS_KEY

# DEBUG: Check environment variable lengths immediately
Write-Host "=== Invoke-CDMCheck.ps1 Debug ==="
Write-Host "Raw env:AWS_SECRET_ACCESS_KEY length: $($env:AWS_SECRET_ACCESS_KEY.Length)"
Write-Host "Script awsSecretAccessKey length: $($script:awsSecretAccessKey.Length)"
Write-Host "Raw env:ENV_AWS_SECRET_ACCESS_KEY length: $($env:ENV_AWS_SECRET_ACCESS_KEY.Length)"
Write-Host "Script envAwsSecretAccessKey length: $($script:envAwsSecretAccessKey.Length)"

# Check if they're the same object
Write-Host "Are they identical? $($env:AWS_SECRET_ACCESS_KEY -eq $script:awsSecretAccessKey)"

# configuration file
if ([string]::IsNullOrEmpty($env:CONFIGURATION_VARIANT_NAME)) {
    $script:configurationFile = ("{0}/{1}" -f $checkDirectory , "configuration.yml")
} else {
    $script:configurationFile = ("{0}/{1}/{2}" -f $checkDirectory, $env:CONFIGURATION_VARIANT_NAME, "configuration.yml")
}

if (Test-Path -Path $checkFile) {
    Write-Information -MessageData ("Running check from '{0}'" -f $checkFile)
} else {
    throw ("Check file '{0}' cannot be found" -f $checkFile)
}

if (Test-Path -Path $configurationFile) {
    Write-Information -MessageData ("Loading configuration from '{0}'" -f $configurationFile)
} else {
    throw ("Configuration file '{0}' cannot be found" -f $configurationFile)
}

if ($skipUntilDateTime -gt $dateTime) {
    Write-Warning ("Skipping CDM check '{0}' until '{1}'`n" -f $env:CHECK_DISPLAY_NAME, $skipUntilDateTime.ToString($env:CDM_DATE_FORMAT))
    Write-Host "##vso[task.complete result=SucceededWithIssues]Skipping CDM check"
} else {
    $parentConfiguration = @{
        dateFormat = $env:CDM_DATE_FORMAT
        dateTime = $dateTime
        stageName = $env:STAGE_NAME
        cdmLibraryDirectory = $env:CDM_LIBRARY_DIRECTORY
        cdmChecksDirectory = $env:CDM_CHECKS_DIRECTORY
        checkDirectory = $checkDirectory
        checkDisplayName = $env:CHECK_DISPLAY_NAME
        checkName = $env:CHECK_NAME
        checkVariantName = $env:CHECK_VARIANT_NAME
        awsAccessKeyId = $awsAccessKeyId
        awsSecretAccessKey = $awsSecretAccessKey
        envAwsKeyId = $envAwsKeyId
        envAwsSecretAccessKey = $envAwsSecretAccessKey
        configurationFile = $configurationFile
    }

    & $checkFile
}
