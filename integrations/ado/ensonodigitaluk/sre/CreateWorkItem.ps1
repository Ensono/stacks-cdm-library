
<#
    This script is responsible for creating and linking the ADO work items for the Ensono Digital SRE ADO project.
#>

# # dot-sourcing functions
$functions = (
   "Find-ADOWorkItemsByQuery.ps1",
   "New-ADOWorkItem.ps1" 
)

foreach ($function in $functions) {
    . ("{0}/powershell/functions/{1}" -f $env:CDM_LIBRARY_DIRECTORY, $function)
}

# // START check for existing Product Backlog Item //
$script:wiTitle = ("{0}: {1} {2} FAILED" -f $(("{0} {1}" -f $parentConfiguration.clientName, "CDM Check")), $parentConfiguration.stageDisplayName, $parentConfiguration.checkDisplayName)

$script:wiPBIQuery = (
    "Select [System.Id],
    [System.Title],
    [System.WorkItemType],
    [System.State]
    From WorkItems
    WHERE [System.WorkItemType] = 'Product Backlog Item'
    AND
    [System.Title] = '{0}'
    AND [State] <> 'Closed'
    AND [State] <> 'Removed'" -f $wiTitle
)

$script:wiPBIs = Find-ADOWorkItemsByQuery -baseURL $parentConfiguration.baseUrl -accessToken $parentConfiguration.accessToken -wiQuery $wiPBIQuery
# // END check for existing Product Backlog Item //

if ($wiPBIs.workItems.Count -eq 0) {
    Write-Information -MessageData ("Creating a new work item with name '{0}'" -f $wiTitle)

    # // START discover work item parent //
    # to avoid a potential clash with the YamlDotNet libary always load the module 'powershell-yaml' last
    Install-PowerShellModules -moduleNames ("powershell-yaml")

    $script:parentMappings = (Get-Content -Path $parentConfiguration.configurationFile |
        ConvertFrom-Yaml).($parentConfiguration.action).parentMappings |
            Where-Object {$_.clientName -eq $parentConfiguration.clientName}

    if ($null -eq $parentMappings.($parentConfiguration.checkName)) {
        throw ("Missing the '{0}' parentMappings configuration for the client '{1}' and check '{2}'" -f $parentConfiguration.action, $parentConfiguration.clientName, $parentConfiguration.checkName)
    }

    $script:wiParentQuery = (
        "SELECT
            [System.Id],
            [System.WorkItemType],
            [System.Title],
            [System.Links.LinkType]
            FROM
            WorkItemLinks
            WHERE
            (
                [Source].[System.WorkItemType] = 'Feature'
                AND [Source].[System.Title] = '{0}'
                AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Reverse'
                AND [Target].[System.Title] = '{1}'
            )" -f $parentMappings.($parentConfiguration.checkName), $parentConfiguration.clientName
    )

    $script:wiParent = (Find-ADOWorkItemsByQuery -baseURL $parentConfiguration.baseUrl -accessToken $parentConfiguration.accessToken -wiQuery $wiParentQuery).workItemRelations.source
    # // STOP discover work item parent //

    # // START creating new PBI //
    $script:wiDescription = (
        "<a href='{0}{1}/_build/results?buildId={2}&view=logs&j={3}'>Build: {4}</a>" -f $parentConfiguration.systemCollectionUri, $parentConfiguration.systemProjectName, $parentConfiguration.buildId, $parentConfiguration.jobId, $parentConfiguration.buildNumber
    )

    $payload = @(
        @{
            op = "add"
            path = "/fields/System.Title"
            from = $null
            value = ("{0}" -f $wiTitle)
        }
        @{
            op = "add"
            path = "/fields/System.Description"
            from = $null
            value = ("{0}" -f $wiDescription)
        }
        @{
            "op"    = "add"
            "path"  = "/fields/System.State"
            "value" = "Refinement"
        }
        @{
            op = "add"
            path = "/fields/Custom.ValuetoBusiness"
            from = $null
            value = ("{0}" -f "4. 5 = Some benefit to one team")
        }
        @{
            op = "add"
            path = "/fields/Custom.RiskReduction"
            from = $null
            value = ("{0}" -f "2. 20 = Major risk to security/vulnerability")
        }
        @{
            op = "add"
            path = "/fields/Custom.JobSize"
            from = $null
            value = ("{0}" -f "5. 8 = 3 Days")
        }
        @{
            op = "add"
            path = "/fields/Custom.TimeCritical"
            from = $null
            value = ("{0}" -f "5. 8 = 1 Month")
        }
        @{
            op = "add"
            path = "/relations/-"
            from = $null
            value = @{
                rel = "System.LinkTypes.Hierarchy-Reverse"
                url = ("{0}" -f $wiParent.url)
            }
        }
    )

    $script:newWI = New-ADOWorkItem -baseURL $parentConfiguration.baseUrl -accessToken $parentConfiguration.accessToken -wiType "Product Backlog Item" -payload $payload

    Write-Information -MessageData ("Work item id '{0}' linked to parent '{1}' with id '{2}'" -f $newWI.id, $parentConfiguration.clientName, $wiParent.id)
    Write-Information -MessageData ("Work item link '{0}/_workitems/edit/{1}'" -f $parentConfiguration.baseUrl, $newWI.id)

    # // STOP creating new PBI //
} else {
    Write-Warning ("Work item with title '{0}' already exists and is not closed or removed" -f $wiTitle)
    Write-Warning ("Please consider skipping this check by updating the pipeline environment variable '{0}' in the file: {1}/{2}/{3}" -f "skip_until", $env:CDM_CHECKS_DIRECTORY, $parentConfiguration.checkName , "pipeline-variables.yml")

    Write-Information -MessageData ("Work item Id: {0}" -f $wiPBIs.workItems.id)
    Write-Information -MessageData ("Work item link '{0}/_workitems/edit/{1}'" -f $parentConfiguration.baseUrl, $wiPBIs.workItems.id)
}
