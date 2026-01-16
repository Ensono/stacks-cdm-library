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
            Write-Host "`nDEBUG`nChecking Ping Directory Server version in namespace: $namespace" # DEBUG
            Write-Host "Cluster Name: $resourceName" # DEBUG
            Write-Host "Resource Region: $resourceRegion" # DEBUG
            Write-Host "Latest Ping Directory Server version to compare against: $latestVersion`n" # DEBUG

            # Update kubeconfig for EKS cluster
            $updateKubeconfig = & aws eks update-kubeconfig --name $resourceName --region $resourceRegion 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error updating kubeconfig:"
                $updateKubeconfig | ForEach-Object { Write-Host $_ }
                throw "Failed to update kubeconfig for EKS cluster $resourceName in region $resourceRegion"
            } else {
                Write-Host "Kubeconfig updated successfully for cluster $resourceName in region $resourceRegion"
            }

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
                $inUpdateRange = $true
            } else {
                $inUpdateRange = $false
            }
        }

        # Set test criteria
        It "Testing that PingDS is in the target version range" {
            $inUpdateRange | Should -Be $true
        }

        AfterAll {
            Write-Host "Up-to-date versions: $($upToDatePatchVersions -join ', ') `n`n`e[3mPlease keep the latest versions file in CDM Library updated, for accurate results.`e[0m"

            if ($inUpdateRange -eq $true) {
                Write-Host "`nINFO: The Ping Directory Server version is up to date. Current version: $version. Latest version: $latestVersion.`n" -ForegroundColor Green
            } elseif ($inUpdateRange -eq $false) {
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
