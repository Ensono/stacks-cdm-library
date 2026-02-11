param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
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
        $pingAmLatestLine = $latestVersionsContent | Where-Object { $_ -match '^pingAmLatest=' }
        if ($pingAmLatestLine) {
            $latestVersion = ($pingAmLatestLine -split '=')[1]
        } else {
            Write-Error "Could not find pingAmLatest in latest_versions file"
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

    Context "Target: <_.hostName>" -ForEach $targets {

        BeforeAll {

            try {
                # Get credentials from environment variables
                $amAdminUser = $env:AMADMIN_USER
                $amAdminPassword = $env:AMADMIN_PASSWORD
                $forgerockFqdn = $env:FORGEROCK_FQDN

                if (-not $amAdminUser -or -not $amAdminPassword -or -not $forgerockFqdn) {
                    throw "Missing required environment variables: AMADMIN_USER, AMADMIN_PASSWORD, or FORGEROCK_FQDN"
                }

                $hostName = $_.hostName
                $amBaseUrl = "https://$hostName"
                
                Write-Host "`nDEBUG`nChecking Ping Access Manager version on host: $hostName" # DEBUG
                Write-Host "Latest Ping Access Manager version to compare against: $latestVersion`n" # DEBUG

                # Authenticate to get token
                Write-Host "Authenticating to Ping AM..."
                $authHeaders = @{
                    "X-OpenAM-Username" = $amAdminUser
                    "X-OpenAM-Password" = $amAdminPassword
                }
                
                $authUri = "$amBaseUrl/am/json/realms/root/authenticate"
                $authResponse = Invoke-RestMethod -Uri $authUri -Method Post -Headers $authHeaders -ErrorAction Stop
                $tokenId = $authResponse.tokenId
                
                if (-not $tokenId) {
                    throw "Failed to retrieve tokenId from authentication response"
                }
                
                Write-Host "Authentication successful, token retrieved"

                # Get version information
                Write-Host "Retrieving Ping AM version..."
                $versionHeaders = @{
                    "Cookie" = "iPlanetDirectoryPro=$tokenId"
                }
                
                $versionUri = "$amBaseUrl/am/json/serverinfo/version"
                $versionResponse = Invoke-RestMethod -Uri $versionUri -Method Get -Headers $versionHeaders -ErrorAction Stop
                $version = $versionResponse.version
                
                Write-Host "`nPing Access Manager version: $version"
            } catch {
                Write-Host "Exception during Ping AM API call: $($_.Exception.Message)"
                throw "Ping AM version check failed: $_"
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
        It "Testing that PingAM is in the target version range" {
            $inUpdateRange | Should -Be $true
        }

        AfterAll {
            Write-Host "Up-to-date versions: $($upToDatePatchVersions -join ', ') `n`n`e[3mPlease keep the latest versions file in CDM Library updated, for accurate results.`e[0m"

            if ($inUpdateRange -eq $true) {
                Write-Host "`nINFO: The Ping Access Manager version is up to date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Green
            } elseif ($inUpdateRange -eq $false) {
                Write-Host "`nWARNING: The Ping Access Manager is out of date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Yellow
            } else {
                Write-Host "`nERROR: Unable to determine if Ping Access Manager needs upgrade. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Red
            }

            Clear-Variable -Name "hostName"
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
    Write-Host "Ping AM version check completed"
}
