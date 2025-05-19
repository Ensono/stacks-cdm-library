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
        
        $module = Get-Module -Name $moduleName -ListAvailable | Sort-Object { $_.Version -as [version] } -Unique -Descending | Select-Object -First 1

        if ($null -eq $module) {
            Write-Information -MessageData ("Installing module")
            
            Retry-Command -ScriptBlock {
                Install-Module -Name $moduleName -Scope CurrentUser -PassThru -Repository PSGallery -Force
            }
            Import-Module -Name $moduleName -Force
            Write-Information -MessageData ("Module: {0} installed with version: {1}`n" -f $moduleName, $((Get-Module -Name $moduleName).Version.ToString()))
            
        } else {
            Write-Information -MessageData ("Module: {0} already installed with version: {1}`n" -f $moduleName, $module.Version.ToString())
            Import-Module -Name $moduleName -Force
        }
    }
}
