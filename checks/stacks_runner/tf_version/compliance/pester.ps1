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

    Write-Host "Discovery:"
    Write-Host ($discovery | Out-String)

    Write-Host "Repositories:"
    Write-Host ($repositories | Out-String)
} 

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    Context "Repo: <_.repo_name>" -ForEach $repositories {

        BeforeAll {
            ls
#            taskctlContextYaml = Get-Content -Raw -Path "$repositories.taskctlContextPath" | ConvertFrom-Yaml
#            $taskctlRunnerImage = $taskctlContextYaml.contexts.powershell.container.name
#            Write-Host ("taskctl runner image '<{0}>'" -f $taskctlRunnerImage)
        }

        It "Sample Test" {
            Write-Host ("TODO")
        }


        # docker pull <taskctl_runner_image>
        # docker run taskctl_runner -- bash -c "terraform init"
        # version contraint check after getting terraform init version

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
