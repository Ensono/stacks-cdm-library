function Retry-Command {
    
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [scriptblock]$scriptBlock,

        [Parameter(Position=1, Mandatory=$false)]
        [int]$maximumRetries = 5,

        [Parameter(Position=2, Mandatory=$false)]
        [int]$delayInMilliseconds = 100
    )

    Begin {
        $retryCount = 0
    }

    Process {
        do {
            $retryCount++

            try {
                # If you want messages from the ScriptBlock
                Write-Information -MessageData ("Attempt: {0}`n" -f $retryCount)
                Invoke-Command -Command $ScriptBlock
                # Otherwise use this command which won't display underlying script messages
                # $scriptBlock.Invoke()
                return
            } catch {
                Write-Error $_ -ErrorAction Continue
                Start-Sleep -Milliseconds $delayInMilliseconds
            }
        } while ($retryCount -lt $maximumRetries)

        # Throw an error after $Maximum unsuccessful invocations. Doesn't need
        # a condition, since the function returns upon successful invocation.
        throw 'Execution failed.'
    }
}
