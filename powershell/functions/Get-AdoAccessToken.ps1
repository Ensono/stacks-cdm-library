Function Get-AdoAccessToken {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $tenantId,
        
        [Parameter(Mandatory = $true)]
        [string]
        $clientId,

        [Parameter(Mandatory = $true)]
        [string]
        $clientSecret
    )

    $InformationPreference = "Continue"
    $ErrorActionPreference = "Stop"
    
    # Build request body
    $body = @{
        'client_id'     = $clientId
        'client_secret' = $clientSecret
        'grant_type'    = 'client_credentials'
        'scope'         = 'https://app.vssps.visualstudio.com/.default'
    }

    # Build request config
    $reqConfig = @{
        Method      = 'POST'
        Uri         = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        Body        = $body
        ContentType = 'application/x-www-form-urlencoded'
        Headers = @{}
    }

    # Make request for access token
    $tokenResponse = Invoke-RestMethod @reqConfig

    if ($null -eq $tokenResponse.access_token) {
        throw "Failed to retrieve access token. Response: $($tokenResponse | ConvertTo-Json)"
    }

    return $tokenResponse.access_token
}