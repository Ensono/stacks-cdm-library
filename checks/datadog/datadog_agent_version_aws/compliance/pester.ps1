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
            Write-Host "`nCurrent Datadog Cluster Agent version: $version"

            # Parse both versions for comparison
            $latestVersionParts = $latestVersion -split '\.'
            $latestMajor = [int]$latestVersionParts[0]
            $latestMinor = [int]$latestVersionParts[1] 
            $latestPatch = [int]$latestVersionParts[2]

            $currentVersionParts = $version -split '\.'
            $currentMajor = [int]$currentVersionParts[0]
            $currentMinor = [int]$currentVersionParts[1] 
            $currentPatch = [int]$currentVersionParts[2]

            # Allow versions within the last 3 minor versions
            $numberOfMinorVersionsToBeConsideredUpToDate = 3
            
            $upToDateVersions = @()
            for ($i = 0; $i -lt $numberOfMinorVersionsToBeConsideredUpToDate; $i++) {
                $minorToCheck = $latestMinor - $i
                if ($minorToCheck -ge 0) {
                    # For each minor version, accept any patch version
                    $upToDateVersions += "$latestMajor.$minorToCheck.*"
                }
            }

            # Compare versions - check if current version is within acceptable range
            $inUpdateRange = $false
            if ($currentMajor -eq $latestMajor) {
                $minorDifference = $latestMinor - $currentMinor
                if ($minorDifference -ge 0 -and $minorDifference -lt $numberOfMinorVersionsToBeConsideredUpToDate) {
                    $inUpdateRange = $true
                }
            }
        }

        # Set test criteria
        It "Testing that Datadog Cluster Agent is in the target version range" {
            $inUpdateRange | Should -Be $true
        }

        AfterAll {
            Write-Host "Up-to-date version range: $($upToDateVersions -join ', ')"

            if ($inUpdateRange -eq $true) {
                Write-Host "`nINFO: The Datadog Cluster Agent version is up to date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Green
            } elseif ($inUpdateRange -eq $false) {
                Write-Host "`nWARNING: The Datadog Cluster Agent is out of date. Current version: $version. Latest version: $latestVersion. Acceptable range: within last $numberOfMinorVersionsToBeConsideredUpToDate minor versions.`n" -ForegroundColor Yellow
            } else {
                Write-Host "`nERROR: Unable to determine if Datadog Cluster Agent needs upgrade. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Red
            }

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
            Clear-Variable -Name "upToDateVersions"
            Clear-Variable -Name "inUpdateRange"
            Clear-Variable -Name "minorDifference"
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
