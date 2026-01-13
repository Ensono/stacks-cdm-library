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
    $gitReposDir = $env:GIT_REPOS_DIR

    Write-Host "Discovery:"
    Write-Host ($discovery | Out-String)

    Write-Host "Repositories:"
    Write-Host ($repositories | Out-String)
} 

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    Context "Repo: <_.repo_name>" -ForEach $repositories {

        BeforeEach {
            $gitReposDir = $env:GIT_REPOS_DIR
            $repoName = $_.repoName
            $versionConstraint = $_.requiredVersionConstraint
            $taskctlContextPath = $_.taskctlContextPath
            $taskctlContextYaml = Get-Content -Raw -Path "$gitReposDir/$repoName/$taskctlContextPath" | ConvertFrom-Yaml
            $taskctlRunnerImage = $taskctlContextYaml.contexts.powershell.container.name
            Write-Host "taskctl runner image: $taskctlRunnerImage"

            docker pull $taskctlRunnerImage | Out-String | Write-Host

            @"
            terraform {
                # https://developer.hashicorp.com/terraform/language/expressions/version-constraints
                required_version = "$versionConstraint"
            }
"@ | Set-Content -Path "./version.tf" -Force

            Get-Content -Path ./version.tf | Write-Host
        }

        It "Terraform init should finish successfully for the given version constraint" {
            Write-Host "Running test for repo: $repoName with version constraint: $versionConstraint"
            docker run --rm -v ./version.tf:/version.tf $taskctlRunnerImage terraform init | Out-String | Write-Host
            $LASTEXITCODE | Should -Be 0
        }
    }
}
