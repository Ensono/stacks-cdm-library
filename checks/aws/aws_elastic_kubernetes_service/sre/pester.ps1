param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    Install-PowerShellModules -moduleNames ("AWS.Tools.Installer")
    
    Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.EKS -Force
    Import-Module -Name "AWS.Tools.Common" -Force
    Import-Module -Name "AWS.Tools.EKS" -Force
    
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Yaml

    # building the discovery objects
    $discovery = $checkConfiguration
    $clusters = $discovery.stages | Where-Object {$_.name -eq $stageName} | Select-Object -ExpandProperty clusters
}

BeforeAll {
    # AWS authentication
    Set-AWSCredential -AccessKey $parentConfiguration.awsAccessKeyId -SecretKey $parentConfiguration.awsSecretAccessKey 
}

Describe $parentConfiguration.checkDisplayName -ForEach $discovery {

    BeforeAll {
        $versionThreshold = $_.versionThreshold
    }

    Context "Cluster: <_.resourceRegion>/<_.resourceName>" -ForEach $clusters {
        BeforeAll {
            $resourceName = $_.resourceName
            $resourceRegion = $_.resourceRegion
    
            try {
                $resource = Get-EKSCluster -Name $resourceName -Region $resourceRegion
            }
            catch {
                throw ("Cannot find resource: '{0}' in region: '{1}'" -f $resourceName, $resourceRegion)
            }

            $currentVersion = $resource.Version
            $targetVersions = (Get-EKSAddonVersion -AddonName 'vpc-cni' -Region $resourceRegion).AddonVersions.Compatibilities.ClusterVersion |
                Sort-Object {$_ -as [version]} -Unique -Descending |
                    Select-Object -First $versionThreshold 
        }

        It "Should have a Status of ACTIVE" {
            $resource.Status | Should -Be "ACTIVE"
        }

        It "The current version should be within target versions" {   
            $targetVersions -contains $currentVersion | Should -Be $true
        }

        AfterAll {
            Write-Information -MessageData ("`nCurrent version {0}" -f $currentVersion)

            Write-Information -MessageData("`nTarget versions (n-{0}) for {1}" -f $versionThreshold, $resourceRegion)
            foreach ($version in $targetVersions) {
                Write-Information -MessageData $version
            }

            Write-Information -MessageData ""

            Clear-Variable -Name "resourceName"
            Clear-Variable -Name "resourceRegion"
            Clear-Variable -Name "resource"
            Clear-Variable -Name "currentVersion"
            Clear-Variable -Name "targetVersions"
        }
    }

    AfterAll {
        Write-Information -MessageData ("`nRunbook: {0}`n" -f $_.runbook)

        Clear-Variable -Name "versionThreshold"
    }
}

AfterAll {
    Clear-AWSCredential
}
