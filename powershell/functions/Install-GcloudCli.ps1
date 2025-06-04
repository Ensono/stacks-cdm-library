Function Install-GcloudCli {
    $InformationPreference = "Continue"
    $ErrorActionPreference = "Stop"

    # When running locally for testing we assume the user already has the gcloud cli installed so we do not install it here. 
    if (-not ($env:AGENT_OS)) {
        return
    }

    # Download gcloud CLI
    $downloadUrl = "https://storage.googleapis.com/cloud-sdk-release/google-cloud-sdk-517.0.0-linux-x86_64.tar.gz"
    try {
        Write-Information -MessageData "Downloading gcloud CLI...`n"
        Invoke-WebRequest -Uri $downloadUrl -OutFile "gcloud.tar.gz"
        Write-Information -MessageData "Downloaded gcloud CLI successfully.`n"
    } catch {
        throw ("Failed to download gcloud CLI: $_")
    }

    # Extract the tar.gz file
    try {
        Write-Information -MessageData "Extracting gcloud CLI...`n"
        tar -xzf gcloud.tar.gz
        Write-Information -MessageData "Extracted gcloud CLI successfully.`n"
    } catch {
        throw ("Failed to extract gcloud CLI: $_")
    }

    # Verify the installation
    Write-Information -MessageData "Verifying glcoud CLI installation...`n"
    if (Test-Path -Path "./google-cloud-sdk/bin/gcloud") {
        ./google-cloud-sdk/bin/gcloud version
        if ($LASTEXITCODE -eq 0) {
            Write-Information -MessageData "`ngcloud CLI installed successfully.`n"
        } else {
            throw ("gcloud CLI installation failed. Error code: $LASTEXITCODE")
        }
    } else {
        throw ("gcloud CLI installation failed.")
    }

    Write-Information -MessageData "Moving gcloud CLI to /usr/local/bin...`n"
    try {
        Move-Item -Path "./google-cloud-sdk/bin/gcloud" -Destination "/usr/local/bin/gcloud" -Force
        Write-Information -MessageData "Moved gcloud CLI successfully.`n"
    } catch {
        throw ("Failed to move gcloud CLI: $_")
    }
}
