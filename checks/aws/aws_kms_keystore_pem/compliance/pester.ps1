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

# For now, I am checking just one cert, but will have to add a foreach loop to be able to check multiple certs with the same check

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {

    }

    Context "Google cloud composer" -ForEach $targets {

        BeforeAll {
            # URL of the .pem file
            $url = $parentConfiguration.certUrl

            # Local path to save the downloaded .pem file
            $localFilePath = "/Users/jasondiaz/Downloads/" # Need to create a local directory in the agent and point to it

            # Download the .pem file
            Invoke-WebRequest -Uri $url -OutFile $localFilePath

            # Load the certificate from the .pem file
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Convert-Path "$localFilePath/payuk.pem"))

            # Define dates for check
            $expDate = $cert.NotAfter
            $today = Get-Date
            $inAMonth = (Get-Date).AddMonths(+1)
            $daysLeft = ($expDate - $today).Days
            $monthsLeft = [int]($daysLeft/30)

            # Check if the certificate is valid and whether it is within the last month of validity
            if ($expDate -eq "" -or $expDate -eq $null -or $expDate -eq 0) {
                throw("ERROR: The ${$_.certName} has not been found or is invalid. The expiry date value cannot be retrieved.")
                $result = 0
            } elseif ($expDate -lt $today) {
                throw("ERROR: The ${$_.certName} has expired.")
                $result = 0
            } elseif ($expDate -ge $today -and $expDate -le $inAMonth) {
                throw("WARNING: The ${$_.certName} needs renewing. $daysLeft days left.")
                $result = 0
            } else {
                throw("INFO: The ${$_.certName} does not need renewing yet. $monthsLeft month(s) still left.")
                $result = 1
            }
        }


        It "Cert is valid for over a month" {
            $result | Should -Be 1
        }
    }
}
