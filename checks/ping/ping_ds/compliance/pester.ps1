<# 
    NOTE: In the configuration for this script, make sure that the AWS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables are set to the 
    Shared account, where the AWS Session Manager target instance is running and a session will need to start for all environments.

    Additionally, envAwsKeyId and envAwsSecretAccessKey variables will need to be set via the parent configuration so that for each 
    environment, the session can connect to the required cluster.
#>

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

    curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
    sudo dpkg -i session-manager-plugin.deb
    
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

        # DEBUG: Check parentConfiguration immediately
        Write-Host "=== Pester.ps1 Debug ==="
        Write-Host "ParentConfiguration awsSecretAccessKey length: $($parentConfiguration.awsSecretAccessKey.Length)"
        Write-Host "ParentConfiguration envAwsSecretAccessKey length: $($parentConfiguration.envAwsSecretAccessKey.Length)"

        $awsAccessKeyId = $parentConfiguration.awsAccessKeyId
        $awsSecretAccessKey = $parentConfiguration.awsSecretAccessKey
        $envAwsKeyId = $parentConfiguration.envAwsKeyId
        $envAwsSecretAccessKey = $parentConfiguration.envAwsSecretAccessKey

         # Check if credentials are empty and throw early
        if ([string]::IsNullOrEmpty($awsAccessKeyId) -or [string]::IsNullOrEmpty($awsSecretAccessKey)) {
            throw "AWS credentials are not set. Check that AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables are configured in the pipeline."
        }
        
        if ([string]::IsNullOrEmpty($envAwsKeyId) -or [string]::IsNullOrEmpty($envAwsSecretAccessKey)) {
            throw "Environment AWS credentials are not set. Check that ENV_AWS_KEY_ID and ENV_AWS_SECRET_ACCESS_KEY environment variables are configured in the pipeline."
        }

        # DEBUG: Check the actual types
        Write-Host "=== Type Analysis ==="
        Write-Host "awsSecretAccessKey type: $($parentConfiguration.awsSecretAccessKey.GetType().FullName)"
        Write-Host "awsSecretAccessKey assigned type: $($awsSecretAccessKey.GetType().FullName)"

        # Handle different object types
        if ($parentConfiguration.awsSecretAccessKey -is [System.Security.SecureString]) {
            Write-Host "Converting SecureString to plain text"
            $awsSecretAccessKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($parentConfiguration.awsSecretAccessKey))
        } elseif ($parentConfiguration.awsSecretAccessKey -is [PSCredential]) {
            Write-Host "Extracting from PSCredential"
            $awsSecretAccessKey = $parentConfiguration.awsSecretAccessKey.GetNetworkCredential().Password
        } else {
            # Force string conversion
            $awsSecretAccessKey = $parentConfiguration.awsSecretAccessKey.ToString()
        }

        # Same for environment credentials
        if ($parentConfiguration.envAwsSecretAccessKey -is [System.Security.SecureString]) {
            Write-Host "Converting env SecureString to plain text"
            $envAwsSecretAccessKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($parentConfiguration.envAwsSecretAccessKey))
        } elseif ($parentConfiguration.envAwsSecretAccessKey -is [PSCredential]) {
            Write-Host "Extracting env from PSCredential"
            $envAwsSecretAccessKey = $parentConfiguration.envAwsSecretAccessKey.GetNetworkCredential().Password
        } else {
            # Force string conversion
            $envAwsSecretAccessKey = $parentConfiguration.envAwsSecretAccessKey.ToString()
        }

        Write-Host "After conversion - awsSecretAccessKey length: $($awsSecretAccessKey.Length)"
        Write-Host "After conversion - envAwsSecretAccessKey length: $($envAwsSecretAccessKey.Length)"
    }

    Context "Target: <_.namespace>/<_.resourceRegion>/<_.resourceName>" -ForEach $targets {

        BeforeAll {
            $resourceName = $_.resourceName
            $resourceRegion = $_.resourceRegion
            $namespace = $_.namespace

            # Enhanced debugging
            Write-Host "=== AWS Credential Debug Information ==="
            Write-Host "Access Key ID Length: $($awsAccessKeyId.Length)"
            Write-Host "Secret Access Key Length: $($awsSecretAccessKey.Length)"
            Write-Host "Access Key ID: $($awsAccessKeyId.Substring(0, 4))...$($awsAccessKeyId.Substring([Math]::Max($awsAccessKeyId.Length-4, 4)))"

            # Check for hidden characters or encoding issues
            $accessKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($awsAccessKeyId)
            $secretKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($awsSecretAccessKey)
            Write-Host "Access Key Byte Length: $($accessKeyBytes.Length)"
            Write-Host "Secret Key Byte Length: $($secretKeyBytes.Length)"

            # Check if secret key looks like it might be Base64 encoded
            if ($awsSecretAccessKey.Length -lt 35) {
                Write-Host "WARNING: Secret key appears to be too short (expected ~40 chars)"
                
                # Try to detect if it's Base64 encoded
                try {
                    $decoded = [System.Convert]::FromBase64String($awsSecretAccessKey)
                    $decodedString = [System.Text.Encoding]::UTF8.GetString($decoded)
                    Write-Host "Possible Base64 decoded length: $($decodedString.Length)"
                    if ($decodedString.Length -gt 35) {
                        Write-Host "Using Base64 decoded secret key"
                        $awsSecretAccessKey = $decodedString
                    }
                } catch {
                    Write-Host "Not Base64 encoded"
                }
            }

            # Clean and validate credentials before setting environment variables
            $cleanAwsAccessKeyId = $awsAccessKeyId.Trim()
            $cleanAwsSecretAccessKey = $awsSecretAccessKey.Trim()

            # Validate credential format
            if ($cleanAwsAccessKeyId -notmatch '^AKIA[0-9A-Z]{16}$') {
            throw "Invalid AWS Access Key ID format: $cleanAwsAccessKeyId"
            }

            # Validate secret key length
            if ($cleanAwsSecretAccessKey.Length -lt 35) {
                throw "AWS Secret Access Key appears to be too short: $($cleanAwsSecretAccessKey.Length) characters (expected ~40)"
            }

            # Set environment variables with cleaned credentials
            $env:AWS_ACCESS_KEY_ID = $cleanAwsAccessKeyId
            $env:AWS_SECRET_ACCESS_KEY = $cleanAwsSecretAccessKey
            $env:AWS_DEFAULT_REGION = $resourceRegion

            # TO BE REMOVED
            Write-Host "Using AWS Key ID: $cleanAwsAccessKeyId to authenticate"
            Write-Host "Using AWS Region: $resourceRegion"
            Write-Host "Final Secret Key Length: $($cleanAwsSecretAccessKey.Length)"

            # Test AWS authentication
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

                # Additional debugging - check environment variables
                Write-Host "Environment variable check:"
                Write-Host "AWS_ACCESS_KEY_ID length: $($env:AWS_ACCESS_KEY_ID.Length)"
                Write-Host "AWS_SECRET_ACCESS_KEY length: $($env:AWS_SECRET_ACCESS_KEY.Length)"

                throw "AWS authentication failed: $_"
            }

            # Prepare commands to run in the remote session
            $commands = @(
                "export AWS_ACCESS_KEY_ID=$envAwsKeyId",
                "export AWS_SECRET_ACCESS_KEY=$envAwsSecretAccessKey",
                "aws eks update-kubeconfig --name $resourceName --region $resourceRegion",
                "kubectl config set-context --current --namespace $namespace",
                "kubectl exec -it ds-cts-0 -n $namespace -c ds -- /opt/opendj/bin/status -V"
            )

            try {
                # Run the commands using SSM send-command
                $sendCommandResult = aws ssm send-command `
                    --instance-ids i-0b9279bc5cfb40f6b `
                    --document-name "AWS-RunShellScript" `
                    --comment "Authenticate and configure kubectl context" `
                    --parameters commands=$commands `
                    --region $resourceRegion `
                    --output text

                # Get the command ID from the result
                $commandId = ($sendCommandResult | Select-String "COMMAND_ID" | ForEach-Object { $_.Line.Split("`t")[-1] }).Trim()

                # Wait for the command to finish and get the output
                Start-Sleep -Seconds 5
                $commandOutput = aws ssm get-command-invocation `
                    --instance-id i-0b9279bc5cfb40f6b `
                    --command-id $commandId `
                    --region $resourceRegion `
                    --output text

                Write-Host "SSM command output:"
                Write-Host $commandOutput

                # You can now parse $commandOutput and use it later in your script
            } catch {
                Write-Error "Failed to send command via SSM: $_"
                exit 1
            }
        }

       # Set test criteria
        $needsUpgrade = $false # Assume no upgrade needed initially - TO BE UPDATED

        It "PingDS is outside the target version threshold" {
            $needsUpgrade | Should -Be $false
        }
    }
}
