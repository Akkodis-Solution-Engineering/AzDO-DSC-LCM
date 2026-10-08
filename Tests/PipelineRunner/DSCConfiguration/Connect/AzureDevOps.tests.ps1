Describe "Actions/Connect/AzureDevOps Action Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $script:actionPath = (Get-FunctionPath 'AzureDevOps.ps1').FullName
        . (Get-FunctionPath 'Import-AzureDevOpsDscCommon.ps1').FullName
        . (Get-FunctionPath 'Invoke-AzDoAuthenticationProvider.ps1').FullName

    }

    Context "When OrganizationName is not supplied" {

        It "should throw" {
            { & $script:actionPath -Context @{} } | Should -Throw "*No 'OrganizationName' supplied*"
        }

    }

    Context "When neither AzureDevOpsDsc.Common nor AzureDevOpsDscNative is available and New-AzDoAuthenticationProvider is not on PATH" {

        BeforeAll {
            # Stub so the mock binds on a host without PowerShellGet; the install must never run.
            function Install-Module { param($Name, $Scope, $Repository, [switch]$Force) }
            Mock Install-Module { throw "no network" }
            Mock Write-Warning { }
            Mock Get-Module { } -ParameterFilter { $ListAvailable }
            Mock Import-Module { throw "module not found" } -ParameterFilter { $Name -eq 'AzureDevOpsDsc.Common' }
        }

        It "should throw a clear, actionable error" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso' } } | Should -Throw "*requires the 'AzureDevOpsDscNative' module*"
        }

    }

    Context "When New-AzDoAuthenticationProvider is already available" {

        BeforeEach {
            function New-AzDoAuthenticationProvider { param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity) }
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

        It "should throw for an unsupported AuthenticationType" {
            { & $script:actionPath -Context @{ OrganizationName = 'contoso'; AuthenticationType = 'Bogus' } } | Should -Throw "*Unsupported AuthenticationType*"
        }

        It "should return null" {
            $result = & $script:actionPath -Context @{ OrganizationName = 'contoso' }
            $result | Should -BeNullOrEmpty
        }

    }

}
