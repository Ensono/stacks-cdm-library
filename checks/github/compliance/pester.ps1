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
    $checkConfiguration = (Get-Content -Path $configurationFile | ConvertFrom-Yaml).($parentConfiguration.checkName)
    
    # GitHub authentication
    $secureString = ($parentConfiguration.githubToken | ConvertTo-SecureString -AsPlainText -Force)
    $credential = New-Object System.Management.Automation.PSCredential "username is ignored", $secureString
    Set-GitHubAuthentication -Credential $credential -SessionOnly

    # building the discovery objects
    $repositories = [System.Collections.ArrayList]@()

    foreach ($repositoryName in $checkConfiguration.repositories) {
        $dependabotPullRequests = Get-GitHubPullRequest -OwnerName $checkConfiguration.owner -RepositoryName $repositoryName |
            Where-Object {$_.state -eq 'open' -and $_.user.login -eq 'dependabot[bot]'} |
                Select-Object -Property title, created_at

        $repositoryObject = [ordered] @{
            repositoryName = $repositoryName
            dependabot = @{
                PRStaleInDays = $checkConfiguration.dependabot.PRStaleInDays
                PRMaxCount = $checkConfiguration.dependabot.PRMaxCount
                pullRequests = $dependabotPullRequests
            }
        }

        $repository = New-Object PSObject -property $repositoryObject
        $repositories.Add($repository)
    }

    $discovery = @{
        runbook = $checkConfiguration.runbook
        owner = $checkConfiguration.owner
        repositories = $repositories
    }

    $dateThreshold = $parentConfiguration.dateTime.AddDays(-$checkConfiguration.dependabot.PRStaleInDays)
}

Describe "<_.owner> $($parentConfiguration.checkDisplayName)" -ForEach $discovery {
    BeforeAll {
        $owner = $_.owner
    }

    Context "Repository: '<_.repositoryName>'" -ForEach $_.repositories {

        BeforeAll {
            Write-Information -MessageData "`n"
            $dateThreshold = $parentConfiguration.dateTime.AddDays(-$_.dependabot.PRStaleInDays)
        }

        It "Dependabot PR '<_.title>' creation date should not be older than $($dateThreshold.ToString($parentConfiguration.dateFormat))" -ForEach $_.dependabot.pullRequests {
            $_.created_at | Should -BeGreaterThan $dateThreshold
        }

        It "The number of Dependabot PRs should be less than or equal to <_.dependabot.PRMaxCount>" {
            $_.dependabot.pullRequests.count | Should -BeLessOrEqual $_.dependabot.PRMaxCount
        }

        AfterAll {
            Write-Information -MessageData ("`nGitHub Pull Request link: http://github.com/{0}/{1}/pulls" -f $owner, $_.repositoryName)
            Clear-Variable -Name "dateThreshold"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)

        Clear-Variable -Name "owner"
    }
}

AfterAll {
    Clear-GitHubAuthentication
}
