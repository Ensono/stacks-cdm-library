param (
    [Parameter(Mandatory = $true)]
    [hashtable] $parentConfiguration
)

BeforeDiscovery {
    # installing dependencies
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("Az.Aks", "powershell-yaml")

    # configuration
    $configurationFile = $parentConfiguration.configurationFile
    $stageName = $parentConfiguration.stageName
    $checkConfiguration = Get-Content -Path $configurationFile | ConvertFrom-Yaml

    # building the discovery objects
    $discovery = $checkConfiguration
    $clusters = $discovery.stages | Where-Object {$_.name -eq $stageName} | Select-Object -ExpandProperty clusters
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
        $versionThreshold = $_.versionThreshold
        $excludePreviewVersions = $_.excludePreviewVersions    
    }

    Context "Cluster: <_.resourceGroupName>/<_.resourceName>" -ForEach $clusters {
        BeforeAll {
            $resourceGroupName = $_.resourceGroupName
            $resourceName = $_.resourceName
    
            try {
                $resource = Get-AzAksCluster -ResourceGroupName $resourceGroupName -Name $resourceName
            }
            catch {
                throw ("Cannot find resource: '{0}' in resource group: '{1}'" -f $resourceName, $resourceGroupName)
            }
    
            $currentSemver = $resource.KubernetesVersion -as [version]
            $currentVersion = ("{0}.{1}" -f $currentSemver.Major, $currentSemver.Minor)

            $aksVersions = (Get-AzAksVersion -Location $resource.Location | Where-Object {$_.IsPreview -ne $excludePreviewVersions}).OrchestratorVersion

            $targetVersions = [System.Collections.ArrayList]@()
            foreach ($aksVersion in $aksVersions) {
                $semverObject = $aksVersion -as [version]
                $targetVersions.Add(("{0}.{1}" -f $semverObject.Major, $semverObject.Minor)) | Out-Null
            }
            $targetVersions = ($targetVersions | Sort-Object { $_-as [version] } -Unique -Descending | Select-Object -First $versionThreshold)
        }

        It "Should have Provisioning State of 'Succeeded'" {
            $resource.ProvisioningState | Should -Be "Succeeded"
        }

        It "The current version should be within target versions" {       
            $targetVersions -contains $currentVersion | Should -Be $true
        }

        AfterAll {
            Write-Information -MessageData ("`nCurrent version {0}" -f $currentVersion)

            Write-Information -MessageData("`nTarget versions (n-{0}) for {1}" -f $versionThreshold, $resource.Location)
            foreach ($version in $targetVersions) {
                Write-Information -MessageData $version
            }

            Write-Information -MessageData ""
            
            Clear-Variable -Name "resourceGroupName"
            Clear-Variable -Name "resourceName"
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
    Clear-AzContext -Scope CurrentUser -Force
}
