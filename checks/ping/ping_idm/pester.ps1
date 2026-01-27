param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    # Install versioning package
    Install-Package -Name NuGet.Versioning -Source nuget.org -Scope CurrentUser -Force -RequiredVersion 7.0.1
    Add-Type -Path (Join-Path (Split-Path (Get-Package NuGet.Versioning).Source) 'lib/net8.0/NuGet.Versioning.dll')

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)

    # building the discovery objects
    $discovery = $checkConfiguration
    $targets = $discovery.stages | Where-Object {$_.name -eq $stageName} | Select-Object -ExpandProperty targets
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    Context "Test" -ForEach $targets {

        It "Resolve PingIDM version" {
            $idm_version = (Invoke-RestMethod -Uri $versionEndpoint -Method Get).productVersion
            Write-Host("PingIDM Version: $idm_version")

            $range = [NuGet.Versioning.VersionRange]::Parse($versionConstraint)
            $nugetVersion = [NuGet.Versioning.NuGetVersion]::Parse($idm_version)
            $range.Satisfies($nugetVersion) | Should -Be $true
        }
    }
}