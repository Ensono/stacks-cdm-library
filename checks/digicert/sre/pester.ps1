param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")
    
    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $checkConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Yaml

    # building the discovery objects
    $discovery = $checkConfiguration
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {
        $parameters = @{
            "method" = "GET"
            "headers" = @{
                "content-type" = "application/json"
                "X-DC-DEVKEY" = $parentConfiguration.digicertAPIkey
            }
        }

        $baseURL = $_.baseURL
        $organisationId = $parentConfiguration.digicertOrganisationId

        $organisationURL = ("{0}/{1}" -f $baseURL, ("organization/{0}" -f $organisationId))
        $reportURL = ("{0}/{1}" -f $baseURL, "report")
        $financeURL = ("{0}/{1}" -f $baseURL, "finance")
    }

    Context "Organisation" {
        
        It "The organisation status should be 'active'" {
            $parameters.Add('uri', ("{0}" -f $organisationURL))
            $response = (Invoke-RestMethod @parameters).status
            
            $response  | Should -BeExactly "active"
        }

        It "The organisation contact and technical contact should be correct" {
            $parameters.Add('uri', ("{0}/{1}" -f $organisationURL, "contact"))
            $response = Invoke-RestMethod @parameters

            $response.organization_contact.name | Should -Be $_.organisationContact
            $response.technical_contact.name | Should -Be $_.technicalContact
        }

        It "The organisation validation (OV) should be valid within the next <_.ordersExpiringRenewBeforeInDays> days" {
            $parameters.Add('uri', ("{0}/{1}" -f $organisationURL, "validation"))
            $response = Invoke-RestMethod @parameters

            ($response.validations | Where-Object {$_.type -eq "ov"}).validated_until |
                Should -BeGreaterThan $parentConfiguration.dateTime.AddDays($_.ordersExpiringRenewBeforeInDays)
        }

        AfterEach {
            $parameters.Remove('uri')
            Clear-Variable -Name "response"
        }
    }

    Context "Orders" {
        
        It "There should be no expirying orders within the next <_.ordersExpiringRenewBeforeInDays> days" {
            $parameters.Add('uri', ("{0}/{1}" -f $reportURL, "order/expiring"))
            $ordersExpiringRenewBeforeInDays = $_.ordersExpiringRenewBeforeInDays

            $response = Invoke-RestMethod @parameters

            ($response.expiring_orders | Where-Object {$_.days_expiring -eq $ordersExpiringRenewBeforeInDays}).order_count | Should -Be 0
        }

        AfterEach {
            $parameters.Remove('uri')
            Clear-Variable -Name "response"
        }
    }

    Context "Finance" {
        
        It "If there are expirying orders within 60 days, the total available funds in USD should be greater than <_.totalAvailableFundsMinInUSD> USD" {
            $parameters.Add('uri', ("{0}/{1}" -f $reportURL, "order/expiring"))

            $response = Invoke-RestMethod @parameters

            if (($response.expiring_orders | Where-Object {$_.days_expiring -eq 60}).order_count -ne 0) {
                Clear-Variable -Name "response"
                $parameters.Remove('uri')
                $parameters.Add('uri', ("{0}/{1}" -f $financeURL, "balance"))

                $response = Invoke-RestMethod @parameters

                [decimal]$response.total_available_funds | Should -BeGreaterOrEqual $_.totalAvailableFundsMinInUSD
            }
        }

        AfterEach {
            $parameters.Remove('uri')
            Clear-Variable -Name "response"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)
        
        Clear-Variable -Name "parameters"
        Clear-Variable -Name "baseURL"
        Clear-Variable -Name "organisationId"
        Clear-Variable -Name "organisationURL"
        Clear-Variable -Name "reportURL"
        Clear-Variable -Name "financeURL"
    }
}
