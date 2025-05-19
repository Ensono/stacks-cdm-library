param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("Az.Accounts", "powershell-yaml")

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)

    # building the discovery objects
    $discovery = $checkConfiguration.stages | Where-Object {$_.name -eq $stageName}
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
    $azContext = Get-AzContext
    if ($azContext.Subscription.Id -eq $parentConfiguration.armSubscriptionId) {
        Write-Information -MessageData ("Reusing Azure context:`n`nTenantId: {0}`nSubscription Name: {1}`nSubscription Id: {2}`n" -f $azContext.Tenant.Id, $azContext.Subscription.Name, $azContext.Subscription.Id)
    } else {
        Write-Information -MessageData ("New Azure context:")
        Clear-AzContext -Force
        
        Connect-Azure `
            -tenantId $parentConfiguration.armTenantId `
            -subscriptionId $parentConfiguration.armSubscriptionId `
            -clientId $parentConfiguration.armClientId `
            -clientSecret $parentConfiguration.armClientSecret
    }
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {        
        
    }

    Context "Subscription" {
        BeforeAll {
            $context = Get-AzContext
            $accessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-AzAccessToken -ResourceUrl "https://management.azure.com" -TenantId $context.Tenant.Id).Token))

            $parameters = @{
                "method" = "GET"
                "headers" = @{
                    "Authorization" = ("Bearer {0}" -f $accessToken )
                    "Accept" = "application/json"
                }
            }

            Write-Host $parameters.headers.Authorization

            $queryParameters = ("api-version={0}" -f "2024-08-01")
        }

        It "Name should be '<_.subscription.name>'" {
            $context.Subscription.Name | Should -Be $_.subscription.name
        }

        It "State should be '<_.subscription.state>'" {
            $context.Subscription.State| Should -Be $_.subscription.state
        }

        It "Offer Id should be '<_.subscription.offerId>'" {
            $parameters.Add('uri', ("{0}/{1}/{2}/{3}/?{4}" -f "https://management.azure.com", "subscriptions", $context.Subscription.Id, "providers/Microsoft.Consumption/usageDetails", $queryParameters))
            (Invoke-RestMethod @parameters | Write-Output).value[0].properties.offerId | Should -Be $_.subscription.offerId
        }

        AfterAll {
            Clear-Variable -Name "context"
            Clear-Variable -Name "accessToken"
            Clear-Variable -Name "parameters"
            Clear-Variable -Name "queryParameters"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)
    }
}

AfterAll {
    Clear-AzContext -Force
}
