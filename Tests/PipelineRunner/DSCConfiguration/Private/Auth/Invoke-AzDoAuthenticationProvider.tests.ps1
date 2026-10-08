Describe "Invoke-AzDoAuthenticationProvider Function Tests" -Tag Unit {

    BeforeAll {
        . (Get-FunctionPath 'Invoke-AzDoAuthenticationProvider.ps1').FullName

        # AzureDevOpsDsc.Common is not loaded in the unit suite; stub the command so Mock binds.
        function New-AzDoAuthenticationProvider { param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity) }

        # The message AzureDevOpsDsc.Common throws when a project is deleted mid sign-in.
        $script:ProjectVanished = "The 'Ieq' operator failed: [Invoke-AzDevOpsApiRestMethod] ... 404 (Not Found) ... TF200016: The following project does not exist: lcm-ci-1-1. ... ProjectDoesNotExistWithNameException"

        Mock Start-Sleep { }
        Mock Write-Warning { }
    }

    It "signs in once when the first attempt succeeds" {
        Mock New-AzDoAuthenticationProvider { }

        Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = 'contoso'; useManagedIdentity = $true }

        Should -Invoke New-AzDoAuthenticationProvider -Exactly 1 -ParameterFilter {
            $OrganizationName -eq 'contoso' -and $useManagedIdentity
        }
        Should -Invoke Start-Sleep -Exactly 0
    }

    It "retries when a project was deleted during sign-in, then succeeds" {
        $script:calls = 0
        Mock New-AzDoAuthenticationProvider {
            $script:calls++
            if ($script:calls -eq 1) { throw $script:ProjectVanished }
        }

        { Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = 'contoso'; useManagedIdentity = $true } } | Should -Not -Throw

        Should -Invoke New-AzDoAuthenticationProvider -Exactly 2
        Should -Invoke Write-Warning -Exactly 1
    }

    It "gives up after MaxAttempts and rethrows the last error" {
        Mock New-AzDoAuthenticationProvider { throw $script:ProjectVanished }

        { Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = 'contoso' } -MaxAttempts 3 } | Should -Throw "*TF200016*"

        Should -Invoke New-AzDoAuthenticationProvider -Exactly 3
    }

    It "does not retry any other failure" {
        Mock New-AzDoAuthenticationProvider { throw "401 (Unauthorized)" }

        { Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = 'contoso' } } | Should -Throw "*401*"

        Should -Invoke New-AzDoAuthenticationProvider -Exactly 1
        Should -Invoke Start-Sleep -Exactly 0
    }
}
