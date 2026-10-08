<#
.SYNOPSIS
Calls New-AzDoAuthenticationProvider, retrying when a project vanishes mid sign-in.

.DESCRIPTION
New-AzDoAuthenticationProvider (AzureDevOpsDsc.Common) warms its caches as part of signing in:
it lists every project in the organization, then reads each one's details. A project deleted
between those two calls - by another pipeline, a person, or a concurrent test run - fails the
second read with TF200016 (ProjectDoesNotExistWithNameException), and the whole sign-in throws.
That is transient: the next attempt lists the organization afresh and no longer sees the project.
So only that error is retried; any other failure (bad credentials, no access, no network) is
thrown straight away.

.PARAMETER Parameters
The parameters to splat to New-AzDoAuthenticationProvider.

.PARAMETER MaxAttempts
How many times to try in total.

.PARAMETER RetryDelaySeconds
How long to wait between attempts.

.EXAMPLE
Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = 'contoso'; useManagedIdentity = $true }
#>
function Invoke-AzDoAuthenticationProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [ValidateRange(0, 300)]
        [int]$RetryDelaySeconds = 5
    )

    for ($attempt = 1; ; $attempt++) {
        try {
            return New-AzDoAuthenticationProvider @Parameters
        }
        catch {
            $projectVanished = "$($_.Exception.Message)" -match 'TF200016|ProjectDoesNotExist'
            if (-not $projectVanished -or $attempt -ge $MaxAttempts) {
                throw
            }

            Write-Warning "[Invoke-AzDoAuthenticationProvider] A project was deleted while signing in to '$($Parameters.OrganizationName)' (attempt $attempt of $MaxAttempts); retrying in $RetryDelaySeconds second(s)."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}
