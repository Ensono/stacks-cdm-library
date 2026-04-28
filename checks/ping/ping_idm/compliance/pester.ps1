param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

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
        $pingIdmLatestLine = $latestVersionsContent | Where-Object { $_ -match '^pingIdmLatest=' }
        if ($pingIdmLatestLine) {
            $latestVersion = ($pingIdmLatestLine -split '=')[1]
        } else {
            Write-Error "Could not find pingIdmLatest in latest_versions file"
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

    Context "Target: <_.versionEndpoint>" -ForEach $targets {

        BeforeAll {

            try {
                $versionEndpoint = $_.versionEndpoint
                Write-Host "`nDEBUG`nChecking PingIDM version on endpoint: $versionEndpoint"
                Write-Host "Latest PingIDM version to compare against: $latestVersion`n"

                $version = (Invoke-RestMethod -Uri $versionEndpoint -Method Get).productVersion
                Write-Host "`nPingIDM version: $version"
            } catch {
                Write-Host "Exception during PingIDM API call: $($_.Exception.Message)"
                throw "PingIDM version check failed: $_"
            }

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
                $inUpdateRange = $true
            } else {
                $inUpdateRange = $false
            }
        }

        # Set test criteria
        It "Testing that PingIDM is in the target version range" {
            $inUpdateRange | Should -Be $true
        }

        AfterAll {
            Write-Host "Up-to-date versions: $($upToDatePatchVersions -join ', ') `n`n`e[3mPlease keep the latest versions file in CDM Library updated, for accurate results.`e[0m"

            if ($inUpdateRange -eq $true) {
                Write-Host "`nINFO: The PingIDM version is up to date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Green
            } elseif ($inUpdateRange -eq $false) {
                Write-Host "`nWARNING: The PingIDM is out of date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Yellow
            } else {
                Write-Host "`nERROR: Unable to determine if PingIDM needs upgrade. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Red
            }

            Clear-Variable -Name "versionEndpoint"
            Clear-Variable -Name "version"
            Clear-Variable -Name "latestVersion"
            Clear-Variable -Name "numberOfPatchVersionsToBeConsideredUpToDate"
            Clear-Variable -Name "latestVersionParts"
            Clear-Variable -Name "majorVersion"
            Clear-Variable -Name "minorVersion"
            Clear-Variable -Name "patchVersion"
            Clear-Variable -Name "upToDatePatchVersions"
            Clear-Variable -Name "inUpdateRange"
        }
    }

    AfterAll {
         Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)

        Clear-Variable -Name "versionThreshold"
    }
}

AfterAll {
    # Clean up any remaining variables
    Write-Host "PingIDM version check completed"
}