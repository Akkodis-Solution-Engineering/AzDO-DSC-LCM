
Describe "Invoke-DscPipelineRunner Function Tests" -Tag Unit {

    BeforeAll {

        # Load the function to test
        $preParseFilePath = (Get-FunctionPath 'Invoke-DscPipelineRunner.ps1').FullName
        . $preParseFilePath

        # Invoke-DscPipelineRunner is a thin wrapper: it authenticates to Azure DevOps then
        # delegates everything else to Invoke-DscRunner, so that's the only downstream call
        # that needs to be mocked/asserted here. Neither AzureDevOpsDsc.Common (mocked out via
        # Import-AzureDevOpsDscCommon below) nor Invoke-DscRunner's own heavy dependency chain
        # are loaded in this test, so the commands are declared as stubs here purely so Pester's
        # Mock has something to intercept.
        function Import-AzureDevOpsDscCommon { }
        function New-AzDoAuthenticationProvider { param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity, $TenantId, $ClientId, [switch]$useGitHubActionsOIDC) }
        function Invoke-DscRunner { param($exportConfigDir, $ConfigurationSourcePath, $ConfigurationRevision, $ConfigurationMode, $ReportPath, [switch]$ContinueOnError, $Engine, $EngineVersion, [switch]$FailOnError, [switch]$KeepTemporaryDirectory) }

        Mock -CommandName Import-AzureDevOpsDscCommon
        Mock -CommandName New-AzDoAuthenticationProvider
        Mock -CommandName Invoke-DscRunner -MockWith { return [pscustomobject]@{ Status = 'Completed' } }
        Mock -CommandName Test-Path -MockWith { return $true }

        $exportConfigDir = New-MockDirectoryPath
        $ConfigurationSourcePath = New-MockDirectoryPath
        $validPat = 'a' * 52
    }

    Context "AzureDevOpsDsc.Common Dependency Check" {

        It "should throw a clear error when AzureDevOpsDsc.Common is not available" {
            Mock -CommandName Import-AzureDevOpsDscCommon -MockWith { throw "Azure DevOps support requires the 'AzureDevOpsDscNative' module." }

            { Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" } |
                Should -Throw "*requires the 'AzureDevOpsDscNative' module*"

            Should -Invoke Invoke-DscRunner -Exactly 0
        }
    }

    Context "Execution Logic" {

        It "should create a ManagedIdentity authentication provider by default" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken"

            Should -Invoke New-AzDoAuthenticationProvider -Exactly 1 -ParameterFilter {
                $OrganizationName -eq "MyOrg" -and $useManagedIdentity
            }
        }

        It "should create a PAT authentication provider when -AuthenticationType 'PAT' is supplied" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" -AuthenticationType "PAT" -PATToken $validPat

            Should -Invoke New-AzDoAuthenticationProvider -Exactly 1 -ParameterFilter {
                $OrganizationName -eq "MyOrg" -and $PersonalAccessToken -eq $validPat
            }
        }

        It "should sign in through GitHub Actions OIDC when -AuthenticationType 'WorkloadIdentity' is supplied" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" -AuthenticationType "WorkloadIdentity" -TenantId "tenant" -ClientId "client"

            Should -Invoke New-AzDoAuthenticationProvider -Exactly 1 -ParameterFilter {
                $OrganizationName -eq "MyOrg" -and $TenantId -eq "tenant" -and $ClientId -eq "client" -and $useGitHubActionsOIDC
            }
        }
    }

    Context "Delegation to Invoke-DscRunner" {

        It "should delegate to Invoke-DscRunner with the mandatory parameters" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken"

            Should -Invoke Invoke-DscRunner -Exactly 1 -ParameterFilter {
                $exportConfigDir -eq $exportConfigDir -and $ConfigurationSourcePath -eq $ConfigurationSourcePath
            }
        }

        It "should return whatever Invoke-DscRunner returns" {
            $result = Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken"

            $result.Status | Should -Be 'Completed'
        }

        It "should forward -ConfigurationRevision, -ConfigurationMode, and -ReportPath when supplied" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" `
                -ConfigurationRevision "main" -ConfigurationMode "Enforce" -ReportPath $exportConfigDir

            Should -Invoke Invoke-DscRunner -Exactly 1 -ParameterFilter {
                $ConfigurationRevision -eq "main" -and $ConfigurationMode -eq "Enforce" -and $ReportPath -eq $exportConfigDir
            }
        }

        It "should forward -ContinueOnError, -EngineVersion, -FailOnError, and -KeepTemporaryDirectory when supplied" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" `
                -ContinueOnError -EngineVersion "3" -FailOnError -KeepTemporaryDirectory

            Should -Invoke Invoke-DscRunner -Exactly 1 -ParameterFilter {
                $ContinueOnError -eq $true -and $EngineVersion -eq "3" -and $FailOnError -eq $true -and $KeepTemporaryDirectory -eq $true
            }
        }

        It "should forward the resolved -Engine" {
            Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath -JITToken "mockToken" -Engine "DscV3"

            Should -Invoke Invoke-DscRunner -Exactly 1 -ParameterFilter {
                $Engine -eq "DscV3"
            }
        }
    }
}
