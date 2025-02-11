param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("Az.Network", "powershell-yaml")

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Yaml
    
    # building the discovery objects
    $discovery = $checkConfiguration
    $gateways = $discovery.stages | Where-Object { $_.name -eq $stageName } | Select-Object -ExpandProperty gateways
    
    $renewalStartDate = $parentConfiguration.dateTime.AddDays($checkConfiguration.certificateRenewalBeforeInDays)
}

BeforeAll {
    # dot-sourcing functions
    $functions = (
        "Connect-Azure.ps1"
    )

    foreach ($function in $functions) {
        . ("{0}/powershell/functions/{1}" -f $env:CDM_LIBRARY_DIRECTORY, $function)
    }
    
    # Azure authentication
    Connect-Azure `
        -tenantId $parentConfiguration.armTenantId `
        -subscriptionId $parentConfiguration.armSubscriptionId `
        -clientId $parentConfiguration.armClientId `
        -clientSecret $parentConfiguration.armClientSecret
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {
        $renewalStartDate = $parentConfiguration.dateTime.AddDays($_.certificateRenewalBeforeInDays)    
    }

    Context "Gateway: <_.resourceGroupName>/<_.resourceName>" -ForEach $gateways {
        BeforeAll {
            $resourceGroupName = $_.resourceGroupName
            $resourceName = $_.resourceName
    
            try {
                $resource = Get-AzApplicationGateway -ResourceGroupName $resourceGroupName -Name $resourceName
            }
            catch {
                throw ("Cannot find resource: '{0}' in resource group: '{1}'" -f $resourceName, $resourceGroupName)
            }
    
            $keyVaultSecretId = $resource.SslCertificates.KeyVaultSecretId
            
            if ([string]::IsNullOrEmpty($keyVaultSecretId)) {
                $certificateBytes = [Convert]::FromBase64String($resource.SslCertificates.PublicCertData)
                $p7b = New-Object System.Security.Cryptography.Pkcs.SignedCms
                $p7b.Decode($certificateBytes)
                $certificateExpiryDate = $p7b.Certificates[0].NotAfter
    
            } else {
                # installing dependencies
                Install-PowerShellModules -moduleNames ("Az.KeyVault")
                
                $elements = $keyVaultSecretId.Split('/')
                $certificateExpiryDate = (Get-AzKeyVaultCertificate -VaultName $elements[2].Split('.')[0] -Name $elements[4]).Expires
            } 

        }

        It "Should have Provisioning State of 'Succeeded'" {
            $resource.ProvisioningState | Should -Be "Succeeded"
        }

        It "The certificate expiry date should be later than $($renewalStartDate.ToString($parentConfiguration.dateFormat))" {    
            $certificateExpiryDate | Should -BeGreaterThan $renewalStartDate
        }

        AfterAll {
            Write-Information -MessageData ("`nApplication Gateway certificate expiry date: {0}`n" -f $certificateExpiryDate.ToString($parentConfiguration.dateFormat))

            Clear-Variable -Name "resourceGroupName"
            Clear-Variable -Name "resourceName"
            Clear-Variable -Name "resource"
            Clear-Variable -Name "keyVaultSecretId"
            Clear-Variable -Name "certificateBytes" -ErrorAction SilentlyContinue
            Clear-Variable -Name "p7b" -ErrorAction SilentlyContinue
            Clear-Variable -Name "certificateExpiryDate"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)

        Clear-Variable -Name "renewalStartDate"
    }
}

AfterAll {
    Clear-AzContext -Scope CurrentUser -Force
}
