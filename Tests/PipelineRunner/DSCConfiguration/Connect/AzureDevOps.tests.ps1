Describe "Actions/Connect/AzureDevOps Action Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $script:actionPath = (Get-FunctionPath 'AzureDevOps.ps1').FullName
        . (Get-FunctionPath 'Import-AzureDevOpsDscCommon.ps1').FullName

    }

    Context "When OrganizationName is not supplied" {

        It "should throw" {
            { & $script:actionPath -Context @{} } | Should -Throw "*No 'OrganizationName' supplied*"
        }

    }

    Context "When neither AzureDevOpsDsc.Common nor AzureDevOpsDscNative is available and New-AzDoAuthenticationProvider is not on PATH" {

        BeforeAll {
            Mock Get-Module { } -ParameterFilter { $ListAvailable }
            Mock Import-Module { throw "module not found" } -ParameterFilter { $Name -eq 'AzureDevOpsDsc.Common' }
        }

        It "should throw a clear, actionable error" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso' } } | Should -Throw "*requires the 'AzureDevOpsDscNative' module*"
        }

    }

    Context "When New-AzDoAuthenticationProvider is already available" {

        BeforeEach {
            function New-AzDoAuthenticationProvider { param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity, $TenantId, $ClientId, [switch]$useGitHubActionsOIDC) }
            Mock New-AzDoAuthenticationProvider { }
        }

        It "should default to ManagedIdentity authentication" {
            & $script:actionPath -Context @{ OrganizationName = 'contoso' } | Out-Null

            Assert-MockCalled New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter {
                $OrganizationName -eq 'contoso' -and $useManagedIdentity -eq $true
            }
        }

        It "should authenticate with ManagedIdentity when explicitly requested" {
            & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'ManagedIdentity' } | Out-Null

            Assert-MockCalled New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter {
                $OrganizationName -eq 'contoso' -and $useManagedIdentity -eq $true
            }
        }

        It "should throw when AuthenticationType is PAT but no PATToken is supplied" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'PAT' } } | Should -Throw "*requires a 'PATToken'*"
        }

        It "should authenticate with a PersonalAccessToken when AuthenticationType is PAT" {
            & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'PAT'; PATToken = 'sekrit' } | Out-Null

            Assert-MockCalled New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter {
                $OrganizationName -eq 'contoso' -and $PersonalAccessToken -eq 'sekrit'
            }
        }

        It "should throw when AuthenticationType is WorkloadIdentity but TenantId or ClientId is missing" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'WorkloadIdentity'; TenantId = 'tenant' } } | Should -Throw "*requires 'TenantId' and 'ClientId'*"
        }

        It "should authenticate through GitHub Actions OIDC when AuthenticationType is WorkloadIdentity" {
            & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'WorkloadIdentity'; TenantId = 'tenant'; ClientId = 'client' } | Out-Null

            Assert-MockCalled New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter {
                $OrganizationName -eq 'contoso' -and $TenantId -eq 'tenant' -and $ClientId -eq 'client' -and $useGitHubActionsOIDC -eq $true
            }
        }

        It "should throw for an unsupported AuthenticationType" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'Bogus' } } | Should -Throw "*Unsupported AuthenticationType*"
        }

        It "should return null" {
            $result = & $script:actionPath -Context @{ OrganizationName = 'contoso' }
            $result | Should -BeNullOrEmpty
        }

    }

}
