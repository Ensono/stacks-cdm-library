Function New-ADOWorkItem {
	
    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false)]
        [hashtable]$headers = @{"content-type" = "application/json-patch+json"},

        [Parameter(Mandatory=$true)]
        [ValidateScript({            
            If ([uri]::IsWellFormedUriString($_,[urikind]::Absolute)) {Return $true}
        })]
        [string]$baseURL,

        [Parameter(Mandatory=$false)]
        [string]$apiVersion = "7.1",

        [Parameter(Mandatory=$true)]
        [string]$accessToken,

        [Parameter(Mandatory=$true)]
        [string]$wiType,
        
        [Parameter(Mandatory=$true)]
        [array]$payload
    )

    $InformationPreference = "Continue"
    $ErrorActionPreference = "Stop"

    $parameters = @{
        method = "POST"
        headers = $headers
    }
    
    $queryParameters = ("api-version={0}" -f $apiVersion)

    $parameters.Add('uri', [URI]::EscapeUriString(("{0}/_apis/{1}?{2}" -f $baseURL, ("wit/workitems/`${0}" -f $wiType), $queryParameters)))
    $parameters.headers.Add('Authorization', ("Basic {0}" -f $accessToken))
    $parameters.Add('body', $($payload | ConvertTo-Json))
    
    $response = Invoke-RestMethod @parameters | Write-Output

    if ($response.GetType().Name -ne "PSCustomObject") {
        throw ("Expected API response object of '{0}' but got '{1}'" -f "PSCustomObject", $response.GetType().Name)
    }
    
    return $response
}
