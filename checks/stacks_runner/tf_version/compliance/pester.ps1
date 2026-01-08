param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    $configurationFile = $parentConfiguration.configurationFile

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)

    # building the discovery objects
    $discovery = $checkConfiguration
    $repositories = $discovery.repositories
    $env_access_token=$env:ADO_ACCESS_TOKEN

    $accessToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($env:ADO_ACCESS_TOKEN)"))
#    Write-Host "Access token after parsing:"
#    Write-Host ($accessToken | Out-String)

    Write-Host "Discovery:"
    Write-Host ($discovery | Out-String)

    Write-Host "Repositories:"
    Write-Host ($repositories | Out-String)
} 

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    Context "Repo: <_.repo_url>" -ForEach $repositories {
        BeforeAll {
#            $header="Authorization: Bearer $accessToken"
#            git -c http.extraheader=$header clone $_.repo_url
#             git clone https://$($env:ADO_ACCESS_TOKEN)@${($_.repo_url -replace "^https://","")}
            git clone "https://$($env:ADO_ACCESS_TOKEN)@dev.azure.com/PayUK/Pay.UK%20API%20Platform/_git/payuk-iac"
            git clone "https://$($env:ADO_ACCESS_TOKEN)@dev.azure.com/PayUK/Pay.UK%20API%20Platform/_git/sre-cdm-checks"
        }

        It "Cloned repository '<_.repo_url>' should exist" {
            $repoName = ($_.repo_url).Split("/")[-1] -replace ".git$",""
            Test-Path -Path "./$repoName" | Should -Be $true
        }
#
#        BeforeEach {
#            @"
#            terraform {
#                # https://developer.hashicorp.com/terraform/language/expressions/version-constraints
#                required_version = "$_"
#            }
#"@ | Set-Content -Path $testFilePath -Force
#        }
#
#        It "'terraform init' should return an Exit Code of 0" {
#            terraform init
#            $LASTEXITCODE | Should -Be 0
#        }
#
#        AfterEach {
#            Remove-Item -Path $testFilePath -Force
#        }
#
#        AfterAll {
#            Clear-Variable -Name testFilePath
#        }
#    }

#    AfterAll {
#        Write-Information -MessageData ("`nInstalled Terraform version: {0}" -f $(terraform --version))
#        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)
    }
}
