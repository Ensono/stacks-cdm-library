param (
    [Parameter(Mandatory = $true)]
    [hashtable]$parentConfiguration
)

BeforeDiscovery {
    # to avoid a potential clash with the YamlDotNet library always load powershell-yaml last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    $configFile = $parentConfiguration.configurationFile
    $config     = (Get-Content -Path $configFile | ConvertFrom-Yaml).amplify_certificate

    $appName    = $config.amplifyAppName
    $awsRegion  = $config.awsRegion
    $acmRegion  = $config.acmRegion
    $thresholds = @($config.expiryAlertThresholds | Sort-Object)
    $now        = [System.DateTime]::UtcNow
    $runbook    = $config.runbook

    # Resolve Amplify app ID from name
    $appsJson = aws amplify list-apps --region $awsRegion --output json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to list Amplify apps: $appsJson" }
    $app = ($appsJson | ConvertFrom-Json).apps | Where-Object { $_.name -eq $appName }
    if (-not $app) { throw "Amplify app '$appName' not found in region '$awsRegion'. Runbook: $runbook" }
    $appId = $app.appId

    # List domain associations
    $domainsJson = aws amplify list-domain-associations --app-id $appId --region $awsRegion --output json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to list domain associations for app '$appId': $domainsJson" }
    $domainAssociations = ($domainsJson | ConvertFrom-Json).domainAssociations

    $script:domains = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($domain in $domainAssociations) {
        $domainName = $domain.domainName

        $detailJson = aws amplify get-domain-association --app-id $appId --domain-name $domainName --region $awsRegion --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to get domain detail for '$domainName': $detailJson" }
        $domainDetail = ($detailJson | ConvertFrom-Json).domainAssociation

        $unverifiedSubdomains = @(
            $domainDetail.subDomains |
            Where-Object { $_.verified -eq $false } |
            ForEach-Object {
                if ($_.subDomainSetting.prefix) { "$($_.subDomainSetting.prefix).$domainName" } else { $domainName }
            }
        )

        $certStatus        = $null
        $daysLeft          = $null
        $notAfterStr       = $null
        $breachedThreshold = $null

        if ($domainDetail.PSObject.Properties['certificate'] -and $domainDetail.certificate.certificateArn) {
            $certArn = $domainDetail.certificate.certificateArn

            $certJson = aws acm describe-certificate --certificate-arn $certArn --region $acmRegion --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to describe ACM certificate '$certArn': $certJson" }
            $cert = ($certJson | ConvertFrom-Json).Certificate

            $certStatus = $cert.Status

            if ($cert.PSObject.Properties['NotAfter']) {
                $notAfter          = [System.DateTime]::Parse($cert.NotAfter).ToUniversalTime()
                $daysLeft          = [int][System.Math]::Floor(($notAfter - $now).TotalDays)
                $notAfterStr       = $notAfter.ToString('yyyy-MM-dd')
                $breachedThreshold = $thresholds | Where-Object { $daysLeft -le $_ } | Sort-Object | Select-Object -First 1
            }
        }

        $script:domains.Add(@{
            DomainName           = $domainName
            UnverifiedSubdomains = $unverifiedSubdomains
            CertStatus           = $certStatus
            DaysLeft             = $daysLeft
            NotAfterStr          = $notAfterStr
            BreachedThreshold    = $breachedThreshold
            Runbook              = $runbook
        })
    }
}

Describe $parentConfiguration.checkDisplayName -ForEach $script:domains {

    Context "Domain: <DomainName>" {

        It "All subdomains should be DNS-verified" {
            $UnverifiedSubdomains | Should -BeNullOrEmpty `
                -Because "Unverified subdomains block Amplify certificate auto-renewal. Runbook: $Runbook"
        }

        It "Certificate should be in ISSUED state" {
            $CertStatus | Should -Be "ISSUED" `
                -Because "Certificate is not in ISSUED state (current: '$CertStatus'). Runbook: $Runbook"
        }

        It "Certificate should not be expiring within the alert threshold" {
            $BreachedThreshold | Should -BeNullOrEmpty `
                -Because "Certificate for '$DomainName' expires in $DaysLeft day(s), within the $BreachedThreshold-day threshold (expiry: $NotAfterStr). Runbook: $Runbook"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: $Runbook`n")
    }
}
