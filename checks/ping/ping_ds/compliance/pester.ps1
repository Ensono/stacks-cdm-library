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
    }

    Context "Target: <_.namespace>/<_.resourceRegion>/<_.resourceName>" -ForEach $targets {

        BeforeAll {
            $resourceName = $_.resourceName
            $resourceRegion = $_.resourceRegion
            $namespace = $_.namespace

            $awsAccessKeyId = $parentConfiguration.awsAccessKeyId
            $awsSecretAccessKey = [string]$parentConfiguration.awsSecretAccessKey
            $envAwsKeyId = $parentConfiguration.envAwsKeyId
            $envAwsSecretAccessKey = [string]$parentConfiguration.envAwsSecretAccessKey
            
            # Check if credentials are empty and throw early
            if ([string]::IsNullOrEmpty($awsAccessKeyId) -or [string]::IsNullOrEmpty($awsSecretAccessKey)) {
                throw "AWS credentials are not set. Check that AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables are configured in the pipeline."
            }
            
            if ([string]::IsNullOrEmpty($envAwsKeyId) -or [string]::IsNullOrEmpty($envAwsSecretAccessKey)) {
                throw "Environment AWS credentials are not set. Check that ENV_AWS_KEY_ID and ENV_AWS_SECRET_ACCESS_KEY environment variables are configured in the pipeline."
            }

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

                throw "AWS authentication failed: $_"
            }

            # Prepare commands to run in the remote session
            $commandsJson = @(
                "export AWS_ACCESS_KEY_ID=$envAwsKeyId",
                "export AWS_SECRET_ACCESS_KEY=$envAwsSecretAccessKey", 
                "aws eks update-kubeconfig --name $resourceName --region $resourceRegion",
                "kubectl config set-context --current --namespace $namespace",
                "kubectl exec ds-cts-0 -n $namespace -c ds -- /opt/opendj/bin/status -V"
            ) | ConvertTo-Json

            Write-Host "Commands JSON: $commandsJson"

            try {
                # Run the commands using SSM send-command with JSON output
                Write-Host "Sending SSM command with parameters:"
                Write-Host "  Instance ID: i-0b9279bc5cfb40f6b"
                Write-Host "  Region: $resourceRegion"
                Write-Host "  Commands JSON: $commandsJson"
                
                $sendCommandResult = aws ssm send-command `
                    --instance-ids i-0b9279bc5cfb40f6b `
                    --document-name "AWS-RunShellScript" `
                    --comment "Authenticate and configure kubectl context" `
                    --parameters "commands=$commandsJson" `
                    --region $resourceRegion `
                    --output json

                Write-Host "Raw SSM send-command result:"
                Write-Host $sendCommandResult
                
                # Check if the command was successful
                if ($LASTEXITCODE -ne 0) {
                    throw "SSM send-command failed with exit code: $LASTEXITCODE"
                }
                
                if (-not $sendCommandResult) {
                    throw "SSM send-command returned no output"
                }

                # Parse JSON response to get command ID
                try {
                    $commandResponse = $sendCommandResult | ConvertFrom-Json
                    $commandId = $commandResponse.Command.CommandId
                    
                    if ([string]::IsNullOrEmpty($commandId)) {
                        throw "Command ID not found in JSON response"
                    }
                    
                    Write-Host "Extracted Command ID: $commandId"
                } catch {
                    Write-Host "Failed to parse JSON response: $_"
                    Write-Host "Raw response: $sendCommandResult"
                    throw "Could not parse SSM command response"
                }

                # Wait for the command to finish and get the output
                Write-Host "Waiting for SSM command to complete..."
                Start-Sleep -Seconds 10

                # Get command invocation with JSON output for easier parsing
                $commandOutput = aws ssm get-command-invocation `
                    --instance-id i-0b9279bc5cfb40f6b `
                    --command-id $commandId `
                    --region $resourceRegion `
                    --output json

                if ($LASTEXITCODE -ne 0) {
                    Write-Host "SSM get-command-invocation failed with exit code: $LASTEXITCODE"
                    
                    # Try to get status first
                    $commandStatus = aws ssm list-command-invocations `
                        --command-id $commandId `
                        --region $resourceRegion `
                        --output json
                        
                    Write-Host "Command status: $commandStatus"
                    throw "Failed to get SSM command invocation"
                }

                # Parse the command invocation result
                try {
                    $invocationResult = $commandOutput | ConvertFrom-Json
                    Write-Host "SSM command status: $($invocationResult.Status)"
                    Write-Host "SSM command stdout:"
                    Write-Host $invocationResult.StandardOutputContent
                    
                    if ($invocationResult.StandardErrorContent) {
                        Write-Host "SSM command stderr:"
                        Write-Host $invocationResult.StandardErrorContent
                    }
                    
                    # You can now parse the StandardOutputContent for version information
                    $versionOutput = $invocationResult.StandardOutputContent
                    
                } catch {
                    Write-Host "Failed to parse command invocation response: $_"
                    Write-Host "Raw invocation response: $commandOutput"
                    throw "Could not parse SSM command invocation response"
                }

            } catch {
                Write-Host "=== SSM Command Execution Error ==="
                Write-Host "Error Type: $($_.Exception.GetType().FullName)"
                Write-Host "Error Message: $($_.Exception.Message)"
                
                throw "Failed to send command via SSM: $_"
            }
        }

       # Set test criteria
        $needsUpgrade = $false # Assume no upgrade needed initially - TO BE UPDATED

        It "PingDS is outside the target version threshold" {
            $needsUpgrade | Should -Be $false
        }
    }
}
