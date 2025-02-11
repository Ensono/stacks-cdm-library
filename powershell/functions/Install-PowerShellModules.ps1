Function Install-PowerShellModules {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]
        $moduleNames
    )

    $InformationPreference = "Continue"
    $ErrorActionPreference = "Stop"
        
    foreach ($moduleName in $moduleNames) {
        Write-Information -MessageData ("`nModule name: {0}" -f $moduleName)
        
        $module = Get-Module -Name $moduleName -ListAvailable

        if ($null -eq $module) {
            Write-Information -MessageData ("Installing module")
            
            Retry-Command -ScriptBlock {
                Install-Module -Name $moduleName -Scope CurrentUser -PassThru -Repository PSGallery -Force
            }
            
            Import-Module -Name $moduleName -Force
        } else {
            Write-Information -MessageData ("Module already installed with version: {0}`n" -f $module.Version)
            Import-Module -Name $moduleName -Force
        }
    }
}
