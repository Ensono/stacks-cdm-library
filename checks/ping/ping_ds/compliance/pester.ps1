param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    Install-PowerShellModules -moduleNames ("AWS.Tools.Installer")
    
    Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.EKS -Force
    Import-Module -Name "AWS.Tools.Common" -Force
    Import-Module -Name "AWS.Tools.EKS" -Force

    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    # install kubectl
    $kubectlInstallOutput = Invoke-Expression "sudo apt-get update && sudo apt-get install -y kubectl" 2>&1
    Write-Host "Kubectl install output: $kubectlInstallOutput"

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)

    # building the discovery objects
    $discovery = $checkConfiguration
    $targets = $discovery.stages | Where-Object {$_.name -eq $stageName} | Select-Object -ExpandProperty targets
}

BeforeAll {

    # Read the latest version from the latest_versions file
    $latestVersionsFile = Join-Path $PSScriptRoot "../.." "latest_versions"

    if (Test-Path $latestVersionsFile) {
        $latestVersionsContent = Get-Content $latestVersionsFile
        $pingDsLatestLine = $latestVersionsContent | Where-Object { $_ -match '^pingDsLatest=' }
        if ($pingDsLatestLine) {
            $latestVersion = ($pingDsLatestLine -split '=')[1]
        } else {
            Write-Error "Could not find pingDsLatest in latest_versions file"
            exit 1
        }
    } else {
        Write-Error "latest_versions file not found at: $latestVersionsFile"
        exit 1
    }
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {
        $versionThreshold = $_.versionThreshold
    }

    Context "Target: <_.namespace>/<_.resourceRegion>/<_.resourceName>" -ForEach $targets {

        BeforeAll {

            $namespace = $_.namespace
            Write-Host "`nDEBUG`nChecking Ping Directory Server version in namespace: $namespace" # DEBUG
            Write-Host "Latest Ping Directory Server version to compare against: $latestVersion`n" # DEBUG

            # Run command on the target instance
            $version = & kubectl exec -it ds-cts-0 -n $namespace -c ds -- /opt/opendj/bin/status -V | head -n 1 | awk '{print $4}' | sed 's/-.*//' 2>&1
            Write-Host "`nPing Directory Server version: $version"

            $numberOfPatchVersionsToBeConsideredUpToDate = 3

            # Create array of up-to-date versions
            $latestVersionParts = $latestVersion -split '\.'
            $majorVersion = [int]$latestVersionParts[0]
            $minorVersion = [int]$latestVersionParts[1] 
            $patchVersion = [int]$latestVersionParts[2]

            $upToDatePatchVersions = @()
            for ($i = 0; $i -lt $numberOfPatchVersionsToBeConsideredUpToDate; $i++) {
                $currentPatch = $patchVersion - $i
                if ($currentPatch -ge 0) {
                    $upToDatePatchVersions += "$majorVersion.$minorVersion.$currentPatch"
                }
            }

            # Compare versions
            if ($upToDatePatchVersions -contains $version) {
                Write-Host "`nINFO: The Ping Directory Server version is up to date. Current version: $version. Latest version: $latestVersion." -ForegroundColor Green
                $needsUpgrade = $false
            } else {
                Write-Host "`nERROR: The Ping Directory Server is out of date. Current version: $version. Latest version: $latestVersion." -ForegroundColor Red
                $needsUpgrade = $true
            }
        }

        # Set test criteria
        It "PingDS is outside the target version threshold" {
            $needsUpgrade | Should -Be $false
        }

        AfterAll {
            Write-Host "Up-to-date versions: $($upToDatePatchVersions -join ', ') `n`n`e[3mPlease keep the latest versions file in CDM Library updated, for accurate results.`e[0m"

            if ($needsUpgrade -eq $false) {
                Write-Host "`nINFO: The Ping Directory Server version is up to date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Green
            } elseif ($needsUpgrade -eq $true) {
                Write-Host "`nWARNING: The Ping Directory Server is out of date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Yellow
            } else {
                Write-Host "`nERROR: Unable to determine if Ping Directory Server needs upgrade. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Red
            }

            Clear-Variable -Name "namespace"
            Clear-Variable -Name "version"
            Clear-Variable -Name "latestVersion"
            Clear-Variable -Name "numberOfPatchVersionsToBeConsideredUpToDate"
            Clear-Variable -Name "latestVersionParts"
            Clear-Variable -Name "majorVersion"
            Clear-Variable -Name "minorVersion"
            Clear-Variable -Name "patchVersion"
            Clear-Variable -Name "upToDatePatchVersions"
            Clear-Variable -Name "needsUpgrade"
        } 
    }

    AfterAll {
         Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)

        Clear-Variable -Name "versionThreshold"
    }
}

AfterAll {
    Clear-AWSCredential
}
