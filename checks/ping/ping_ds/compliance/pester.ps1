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
            $kConfigContext = "kubectl config set-context --current --namespace $namespace"
            $kubectlCommand = "kubectl exec -it ds-cts-0 -n $namespace -c ds -- /opt/opendj/bin/status -V"

            try {
                # Update kubeconfig
                Write-Host "Updating kubeconfig for EKS cluster: $resourceName in region: $resourceRegion"
                $kubeConfOutput = Invoke-Expression $eksKubecnfCommand 2>&1
                Write-Host "Kubeconfig update output: $kubeConfOutput"

                Write-Host "Updating K8s config context in the agent to use namespace: $namespace"
                $kConfigOutput = Invoke-Expression $kConfigContext 2>&1
                Write-Host "K8s config context update output: $kConfigOutput"

                # Check if kubeconfig update was successful
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to update kubeconfig. Exit code: $LASTEXITCODE. Output: $kubeConfOutput"
                }
                
                # Test kubectl connectivity first
                Write-Host "Testing kubectl connectivity..."
                try {
                    $connectivityTest = & kubectl get namespaces 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        $connectivityErrorString = $connectivityTest | Out-String
                        throw "kubectl connectivity test failed. Exit code: $LASTEXITCODE. Error: $connectivityErrorString"
                    }
                } catch {
                    throw "kubectl connectivity test failed with exception: $($_.Exception.Message)"
                }
                
                # Execute the kubectl command and capture output with better error handling
                Write-Host "Executing kubectl command to get PingDS version..."
                $output = Invoke-Expression $kubectlCommand 2>&1
                
                # Check the exit code to determine if the command was successful
                if ($LASTEXITCODE -ne 0) {
                    $errorMessage = "kubectl command failed with exit code: $LASTEXITCODE"
                    
                    # Analyze the output to provide more specific error messages
                    $outputString = $output | Out-String
                    
                    if ($outputString -match "pod.*not found") {
                        $errorMessage += ". Pod 'ds-cts-0' not found in namespace '$namespace'"
                    }
                    elseif ($outputString -match "container.*not found") {
                        $errorMessage += ". Container 'ds' not found in pod 'ds-cts-0'"
                    }
                    elseif ($outputString -match "unable to upgrade connection") {
                        $errorMessage += ". Unable to establish connection to pod (possibly network issues)"
                    }
                    elseif ($outputString -match "authentication") {
                        $errorMessage += ". Authentication failed - check kubectl credentials"
                    }
                    elseif ($outputString -match "authorization") {
                        $errorMessage += ". Authorization failed - insufficient permissions"
                    }
                    elseif ($outputString -match "timeout") {
                        $errorMessage += ". Command timed out - pod may be unresponsive"
                    }
                    elseif ($outputString -match "No such file or directory") {
                        $errorMessage += ". OpenDJ binary not found at expected path '/opt/opendj/bin/status'"
                    }
                    elseif ($outputString -match "Connection refused") {
                        $errorMessage += ". Connection to PingDS server refused - service may be down"
                    }
                    else {
                        $errorMessage += ". Error output: $outputString"
                    }
                    
                    throw $errorMessage
                }
                
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
                        if ($minorDiff -gt $versionThreshold) { # Use versionThreshold from configuration
                            $needsUpgrade = $true
                        }
                    }
                    
                    if ($needsUpgrade) {
                        Write-Host "PingDS needs to be upgraded" -ForegroundColor Red
                    } else {
                        Write-Host "PingDS does not need upgrading" -ForegroundColor Green
                    }
                } else {
                    throw "No version number found in the expected format (x.y.z). Output: $outputString"
                }
            } catch {
                $errorDetails = @{
                    'Command' = $kubectlCommand
                    'Namespace' = $namespace
                    'Resource' = $resourceName
                    'Region' = $resourceRegion
                    'Error' = $_.Exception.Message
                    'Timestamp' = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                Write-Error "PingDS version check failed: $($_.Exception.Message)"
                Write-Host "Error Details:" -ForegroundColor Red
                $errorDetails | Format-Table -AutoSize
                
                # Re-throw the error so the Pester test fails appropriately
                throw $_
            }
        }

       # Set test criteria
        It "PingDS is outside the target version threshold" {
            $needsUpgrade | Should -Be $false
        }
    }
}
