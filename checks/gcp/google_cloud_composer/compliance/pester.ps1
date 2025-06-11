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
    # Dot-sourcing functions
    $functions = (
        "Install-GcloudCli.ps1"
    )

    foreach ($function in $functions) {
        . ("{0}/powershell/functions/{1}" -f $env:CDM_LIBRARY_DIRECTORY, $function)
    }

    # # Install Google Cloud CLI
    # try {
    #     Install-GcloudCli
    # }
    # catch {
    #     throw ("Cannot install Google Cloud CLI: {0}" -f $_.Exception.Message)
    # }

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

    Context "Google cloud composer" -ForEach $targets {

        BeforeAll {
            gcloud config set project $_.project
            if ($LASTEXITCODE -ne 0) {
                throw ("gcloud CLI project configuration failed. Error code: $LASTEXITCODE")
            }
    
            gcloud config set composer/location $_.location
            if ($LASTEXITCODE -ne 0) {
                throw ("gcloud CLI zone configuration failed. Error code: $LASTEXITCODE")
            }

            gcloud config set core/format json
            if ($LASTEXITCODE -ne 0) {
                throw ("gcloud CLI default format set to json failed. Error code: $LASTEXITCODE")
            }
            
            $res = gcloud composer environments list-upgrades --format json $_.environment 2>$null | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) {
                throw ("gcloud CLI list upgrades failed. Error code: $LASTEXITCODE")
            }

            Write-Host $res
        }

        it "Should not have any upgrades available" {
            $res.imageVersionId | should -be ""
        }

    }
}
