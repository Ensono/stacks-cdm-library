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
            $latestVersion = ($pingDsLatestLine -split '=')[1].Trim('"')
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
            $resourceName = $_.resourceName
            $resourceRegion = $_.resourceRegion
            $namespace = $_.namespace
            $eksKubecnfCommand = "aws eks update-kubeconfig --name $resourceName --region $resourceRegion"
            $kubectlCommand = "kubectl exec -it ds-cts-0 -n $namespace -c ds -- /opt/opendj/bin/status -V"

            try {
                # Update kubeconfig
                $kubeConfOutput = Invoke-Expression $eksKubecnfCommand 2>&1
                Write-Host "Kubeconfig update output: $kubeConfOutput"
                # Execute the kubectl command and capture output
                $output = Invoke-Expression $kubectlCommand 2>&1
                Write-Host "Kubectl command output: $output"
                
                # Convert output to string if it's not already
                $outputString = $output | Out-String
                
                # Use regex to find version number in format x.y.z
                $versionPattern = '\b\d+\.\d+\.\d+\b'
                $versionMatch = [regex]::Match($outputString, $versionPattern)
                
                if ($versionMatch.Success) {
                    $currentVersion = $versionMatch.Value
                    Write-Host "Current PingDS version: $currentVersion"
                    Write-Host "Latest available version: $latestVersion"
                    
                    # Parse version numbers for comparison
                    $currentVersionParts = $currentVersion.Split('.') | ForEach-Object { [int]$_ }
                    $latestVersionParts = $latestVersion.Split('.') | ForEach-Object { [int]$_ }
                    
                    $currentMajor = $currentVersionParts[0]
                    $currentMinor = $currentVersionParts[1]
                    $latestMajor = $latestVersionParts[0]
                    $latestMinor = $latestVersionParts[1]
                    
                    # Check if current version needs upgrading
                    $needsUpgrade = $false
                    
                    # If not on latest major version, needs upgrade
                    if ($currentMajor -lt $latestMajor) {
                        $needsUpgrade = $true
                    }
                    # If on latest major version, check if more than 2 minor versions behind
                    elseif ($currentMajor -eq $latestMajor) {
                        $minorDiff = $latestMinor - $currentMinor
                        if ($minorDiff -gt 2) { # Pass the number of versions via parentConfiguration - versionThreshold
                            $needsUpgrade = $true
                        }
                    }
                    
                    if ($needsUpgrade) {
                        Write-Host "PingDS needs to be upgraded" -ForegroundColor Red
                    } else {
                        Write-Host "PingDS does not need upgrading" -ForegroundColor Green
                    }
                } else {
                    Write-Warning "No version number found in the expected format (x.y.z)"
                    Write-Host "Full output:"
                    Write-Host $outputString
                }
            } catch {
                Write-Error "Failed to execute kubectl command: $_"
            }
        }

       # Set test criteria
        It "PingDS is outside the target version threshold" {
            $needsUpgrade | Should -Be $false
        }
    }
}
