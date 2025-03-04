<#
    This is the CDM check
    The validation could be directly in this file or via a testing framwework such as Pester - https://pester.dev/
#>

# installing dependencies
Install-PowerShellModules -moduleNames ("Pester")

# pester file
if (Test-Path -Path ("{0}/{1}/{2}" -f $parentConfiguration.cdmChecksDirectory, $parentConfiguration.checkName, "pester.ps1")) {
    $script:pesterFile = ("{0}/{1}/{2}" -f $parentConfiguration.cdmChecksDirectory, $parentConfiguration.checkName, "pester.ps1")
} else {
    if([string]::IsNullOrEmpty($parentConfiguration.checkVariantName)) {
        throw ("When running Pester from the CDM library a variant check must be set using the pipeline variable 'check_variant_name'")
    }
    $script:pesterFile = ("{0}/{1}/{2}/{3}/{4}" -f $parentConfiguration.cdmLibraryDirectory, $parentConfiguration.cdmChecksDirectory, $parentConfiguration.checkName, $parentConfiguration.checkVariantName, "pester.ps1")
}

if (Test-Path -Path $pesterFile) {
    Write-Information -MessageData ("Running Pester from '{0}'" -f $pesterFile)
} else {
    throw ("Pester file '{0}' cannot be found" -f $pesterFile)
}

# output file
if ([string]::IsNullOrEmpty(($parentConfiguration.checkName).split("/")[1])) {
    $script:outputFile = ("{0}_{1}" -f $parentConfiguration.checkName, "results.xml")
} else {
    $script:outputFile = ("{0}_{1}" -f ($parentConfiguration.checkName).split("/")[1], "results.xml")
}

# configuration available in the discovery and run phases of Pester
$script:pesterContainer = New-PesterContainer -Path $pesterFile -Data @{
    parentConfiguration = $parentConfiguration
}

# Pester configuration - https://pester.dev/docs/usage/configuration
$script:pesterConfiguration = [PesterConfiguration] @{
    Run = @{
        Container = $pesterContainer
    }
    Output = @{
        Verbosity = 'Detailed'
    }
    TestResult = @{
        Enabled      = $true
        OutputFormat = "NUnitXml"
        OutputPath   = ("{0}/{1}" -f $parentConfiguration.checkDirectory, $outputFile)
    }
}

Invoke-Pester -Configuration $pesterConfiguration

Write-Information -MessageData `n
