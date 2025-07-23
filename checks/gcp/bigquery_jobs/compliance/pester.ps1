param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # Installing dependencies

    Install-PowerShellModules -moduleNames ("powershell-yaml")

    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)

    # Building the discovery objects
    $discovery = $checkConfiguration
    $targets = $discovery.stages | Where-Object { $_.name -eq $stageName } | Select-Object -ExpandProperty targets
}

BeforeAll {
    # Authenticate gcloud Cli
    $LASTEXITCODE = 0
    gcloud auth login --cred-file $parentConfiguration.secureFilePath --no-launch-browser --quiet --force
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud CLI authentication failed. Error code: $LASTEXITCODE"
    }
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {

    }

    Context "Big Query Jobs" -ForEach $targets {

        BeforeAll {

            # Parse start and end times

            if ($_.startTime) {
                $minCreationTime = [System.DateTimeOffset]::new((Get-Date $_.startTime)).ToUnixTimeMilliseconds()
            }

            if ($_.endTime) {
                $maxCreationTime = [System.DateTimeOffset]::new((Get-Date $_.endTime)).ToUnixTimeMilliseconds()
            }
            
            $GcpAccessToken = gcloud auth print-access-token
            if ($LASTEXITCODE -ne 0) {
                throw ("gcloud CLI access token retrieval failed. Error code: $LASTEXITCODE")
            }

            # Verify path param
            if (-not $_.project) {
                throw "Project is not specified in the check configuration"
            }

            # Build query params
            $queryParams = "?allUsers=true&projection=FULL"

            if ($_.maxResults) {
                $queryParams += "&maxResults=$($_.maxResults)"
            }

            if ($minCreationTime) {
                $queryParams += "&minCreationTime=$($minCreationTime)"
            }

            if ($maxCreationTime) {
                $queryParams += "&maxCreationTime=$($maxCreationTime)"
            }

            # Build the API URL
            $Url = "https://bigquery.googleapis.com/bigquery/v2/projects/$($_.project)/jobs$queryParams"

            $headers = @{
                "Authorization" = "Bearer $GcpAccessToken"
            }

            $response = Invoke-WebRequest -Uri $Url -Method Get -Headers $headers -ErrorAction Stop
            if ($response.StatusCode -ne 200) {
                throw "Failed to retrieve BigQuery jobs. HTTP Status Code: $($response.StatusCode)"
            }

            $results = $response.content | ConvertFrom-Json

            # Filter for extract (backup jobs) where an error was reported
            $jobType = $_.jobType

            $failedBackupJobs = $results.jobs | Where-Object {
                $_.configuration.jobType -eq $jobType -and $null -ne $_.status.errorResult
            }

        }

        it "Should have no failed backup jobs" {
            $failedBackupJobs.Count | should -be 0
        }

        AfterAll {
            if ($failedBackupJobs.Count -gt 0) {
                Write-Host "`n=== FAILED JOBS ==="
                $failedBackupJobs | ForEach-Object {
                    $jobId = $_.id
                    $jobName = $_.jobReference.jobId
                    $errorMessage = $_.status.errorResult.message

                    Write-Host "`nJob ID: $jobId"
                    Write-Host "Job Name: $jobName"
                    Write-Host "Error Message: $errorMessage`n"
                }
            }
        }
    }
}
