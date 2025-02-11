param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("PowerShellForGitHub", "powershell-yaml")

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $checkConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Yaml
    
    # GitHub authentication
    $secureString = ($parentConfiguration.githubToken | ConvertTo-SecureString -AsPlainText -Force)
    $credential = New-Object System.Management.Automation.PSCredential "username is ignored", $secureString
    Set-GitHubAuthentication -Credential $credential -SessionOnly

    # building the discovery objects
    $repositories = [System.Collections.ArrayList]@()

    foreach ($repositoryName in $checkConfiguration.repositories) {
        $pullRequests = Get-GitHubPullRequest -OwnerName $checkConfiguration.owner -RepositoryName $repositoryName |
            Where-Object {$_.state -eq 'open' -and $_.user.login -eq 'dependabot[bot]'} |
                Select-Object -Property title, created_at

        $repositoryObject = [ordered] @{
            repositoryName = $repositoryName
            dependabotPRStaleInDays = $checkConfiguration.dependabotPRStaleInDays
            dependabotPRMaxCount = $checkConfiguration.dependabotPRMaxCount
            pullRequests = $pullRequests
        }

        $repository = New-Object PSObject -property $repositoryObject
        $repositories.Add($repository)
    }

    $discovery = @{
        runbook = $checkConfiguration.runbook
        owner = $checkConfiguration.owner
        repositories = $repositories
    }

    $dateThreshold = $parentConfiguration.dateTime.AddDays(-$checkConfiguration.dependabotPRStaleInDays)
}

Describe "<_.owner> $($parentConfiguration.checkDisplayName)" -ForEach $discovery {

    Context "Repository: '<_.repositoryName>'" -ForEach $_.repositories {

        BeforeAll {
            Write-Information -MessageData "`n"
            $dateThreshold = $parentConfiguration.dateTime.AddDays(-$_.dependabotPRStaleInDays)
        }

        It "Dependabot PR '<_.title>' creation date should not be older than $($dateThreshold.ToString($parentConfiguration.dateFormat))" -ForEach $_.pullRequests {
            $_.created_at | Should -BeGreaterThan $dateThreshold
        }

        It "The number of Dependabot PRs should be less than or equal to <_.dependabotPRMaxCount>" {
            $_.pullRequests.count | Should -BeLessOrEqual $_.dependabotPRMaxCount
        }

        AfterAll {
            Write-Information -MessageData ("`nGitHub Pull Request link: http://github.com/{0}/{1}/pulls" -f $_.owner, $_.repositoryName)
            Clear-Variable -Name "dateThreshold"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)
    }
}

AfterAll {
    Clear-GitHubAuthentication
}
