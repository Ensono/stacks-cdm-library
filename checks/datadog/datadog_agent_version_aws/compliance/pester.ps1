param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # install AWS CLI
    try {
        $awsCliCheck = & aws --version 2>&1
        Write-Host "AWS CLI already installed: $awsCliCheck"
    } catch {
        Write-Host "Installing AWS CLI..."
        $awsCliInstallOutput = Invoke-Expression "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install" 2>&1
        Write-Host "AWS CLI install output: $awsCliInstallOutput"
    }

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

    # Fetch the latest Datadog Cluster Agent version from GitHub API
    Write-Host "Fetching latest Datadog Cluster Agent version from GitHub..."
    try {
        $gitHubApiUrl = "https://api.github.com/repos/DataDog/datadog-agent/releases/latest"
        $response = Invoke-RestMethod -Uri $gitHubApiUrl -Headers @{
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "PowerShell-Pester-Check"
        }
        $latestVersion = $response.tag_name -replace '^v', ''  # Remove 'v' prefix if present
        Write-Host "Latest Datadog Cluster Agent version from GitHub: $latestVersion"
    } catch {
        Write-Error "Failed to fetch latest Datadog Cluster Agent version from GitHub: $_"
        exit 1
    }
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {
        $versionThreshold = $_.versionThreshold
    }

    Context "Target: <_.namespace>/<_.deploymentName>/<_.resourceRegion>/<_.resourceName>" -ForEach $targets {

        BeforeAll {

            try {
                # First test with AWS CLI version to ensure it's working
                $awsVersion = & aws --version 2>&1
                Write-Host "AWS CLI Version: $awsVersion"

                # Test authentication
                $authTest = & aws sts get-caller-identity --output json 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Raw AWS CLI Error Output:"
                    $authTest | ForEach-Object { Write-Host $_ }
                    
                    # Try alternative authentication method
                    Write-Host "Trying alternative authentication..."
                    $authTest2 = & aws sts get-caller-identity --no-cli-pager 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "AWS authentication failed with exit code $LASTEXITCODE"
                    } else {
                        $authTest = $authTest2
                    }
                }

                $authResult = $authTest | ConvertFrom-Json
                Write-Host "AWS authentication successful. Account: $($authResult.Account), User: $($authResult.Arn)"
            } catch {
                Write-Host "Exception during AWS authentication: $($_.Exception.Message)"
                Write-Host "Final credential lengths - AccessKey: $($cleanAwsAccessKeyId.Length), SecretKey: $($cleanAwsSecretAccessKey.Length)"

                throw "AWS authentication failed: $_"
            }

            $resourceName = $_.resourceName
            $resourceRegion = $_.resourceRegion
            $namespace = $_.namespace
            $deploymentName = $_.deploymentName
            Write-Host "`nDEBUG`nChecking Datadog Cluster Agent version" # DEBUG
            Write-Host "Cluster Name: $resourceName" # DEBUG
            Write-Host "Resource Region: $resourceRegion" # DEBUG
            Write-Host "Namespace: $namespace" # DEBUG
            Write-Host "Deployment Name: $deploymentName" # DEBUG
            Write-Host "Latest Datadog Cluster Agent version to compare against: $latestVersion`n" # DEBUG

            # Update kubeconfig for EKS cluster
            $updateKubeconfig = & aws eks update-kubeconfig --name $resourceName --region $resourceRegion 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error updating kubeconfig:"
                $updateKubeconfig | ForEach-Object { Write-Host $_ }
                throw "Failed to update kubeconfig for EKS cluster $resourceName in region $resourceRegion"
            } else {
                Write-Host "Kubeconfig updated successfully for cluster $resourceName in region $resourceRegion"
            }

            # Get the current Datadog Cluster Agent version from the cluster
            # Query the deployment using variables from configuration
            $deploymentDescription = & kubectl describe deploy $deploymentName -n $namespace 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error fetching Datadog Cluster Agent deployment:"
                $deploymentDescription | ForEach-Object { Write-Host $_ }
                throw "Failed to fetch deployment $deploymentName in namespace $namespace"
            }

            # Extract version from the image tag
            $imageLine = $deploymentDescription | Select-String "Image" | Select-Object -First 1
            if (-not $imageLine) {
                throw "No Image field found in deployment $deploymentName"
            }

            $version = $imageLine.ToString().Split(':')[-1].Trim()
            
            # Parse both versions for comparison
            $latestVersionParts = $latestVersion -split '\.'
            $latestMajor = [int]$latestVersionParts[0]
            $latestMinor = [int]$latestVersionParts[1] 
            $latestPatch = [int]$latestVersionParts[2]

            $currentVersionParts = $version -split '\.'
            $currentMajor = [int]$currentVersionParts[0]
            $currentMinor = [int]$currentVersionParts[1] 
            $currentPatch = [int]$currentVersionParts[2]

            # Calculate version differences
            $majorVersionsBehind = $latestMajor - $currentMajor
            $minorVersionsBehind = $latestMinor - $currentMinor

            # Display version comparison
            Write-Host "`nCluster Version: $version"
            Write-Host "Latest Version: $latestVersion"
            Write-Host ""
            Write-Host "Cluster: Major=$currentMajor Minor=$currentMinor Patch=$currentPatch"
            Write-Host "Latest:  Major=$latestMajor Minor=$latestMinor Patch=$latestPatch"
            Write-Host ""
            Write-Host "Major versions behind: $majorVersionsBehind"
            Write-Host "Minor versions behind: $minorVersionsBehind"
            Write-Host ""
            Write-Host "=== RESULT ==="

            # Allow versions within the last 10 minor versions
            $numberOfMinorVersionsToBeConsideredUpToDate = 10
            
            # Compare versions - check if current version is within acceptable range
            $inUpdateRange = $false
            if ($majorVersionsBehind -eq 0) {
                if ($minorVersionsBehind -ge 0 -and $minorVersionsBehind -le $numberOfMinorVersionsToBeConsideredUpToDate) {
                    $inUpdateRange = $true
                    Write-Host "Minor version is $minorVersionsBehind version(s) behind"
                    Write-Host "Status: UPDATED" -ForegroundColor Green
                } else {
                    Write-Host "Minor version is $minorVersionsBehind version(s) behind"
                    Write-Host "Status: OUTDATED" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Major version is $majorVersionsBehind version(s) behind"
                Write-Host "Status: OUTDATED" -ForegroundColor Yellow
            }
        }

        # Set test criteria
        It "Testing that Datadog Cluster Agent is in the target version range" {
            $inUpdateRange | Should -Be $true
        }

        AfterAll {
            Write-Host ""

            Clear-Variable -Name "namespace"
            Clear-Variable -Name "deploymentName"
            Clear-Variable -Name "version"
            Clear-Variable -Name "latestVersion"
            Clear-Variable -Name "numberOfMinorVersionsToBeConsideredUpToDate"
            Clear-Variable -Name "latestVersionParts"
            Clear-Variable -Name "latestMajor"
            Clear-Variable -Name "latestMinor"
            Clear-Variable -Name "latestPatch"
            Clear-Variable -Name "currentVersionParts"
            Clear-Variable -Name "currentMajor"
            Clear-Variable -Name "currentMinor"
            Clear-Variable -Name "currentPatch"
            Clear-Variable -Name "majorVersionsBehind"
            Clear-Variable -Name "minorVersionsBehind"
            Clear-Variable -Name "inUpdateRange"
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
