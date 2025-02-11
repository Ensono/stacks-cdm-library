Function Connect-Azure {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $tenantId,
        
        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionId,

        [Parameter(Mandatory = $true)]
        [string]
        $clientId,

        [Parameter(Mandatory = $true)]
        [string]
        $clientSecret
    )

    $InformationPreference = "Continue"
    $ErrorActionPreference = "Stop"
    
    . $PSScriptRoot/Install-PowerShellModules.ps1
    Install-PowerShellModules -moduleNames ("Az.Accounts")

    $secureClientSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $secureClientSecret
    Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $credential -Subscription $subscriptionId

    $azContext = Get-AzContext
    return Write-Information -MessageData ("`nTenantId: {0}`nSubscription Name: {1}" -f $azContext.Tenant.Id, $azContext.Subscription.Name)
}
