
Describe "Invoke-AZDoLCM Function Tests" -Tag Unit {

    BeforeAll {

        # Load the function to test, and Invoke-DscLCM so its real signature is known before mocking it
        $preParseFilePath = (Get-FunctionPath 'Invoke-AZDoLCM.ps1').FullName
        . (Get-FunctionPath 'Invoke-DscLCM.ps1').FullName
        . $preParseFilePath

        # Mock Authentication Provider Function
        Function New-AzDoAuthenticationProvider {
            param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity)
        }

        Mock -CommandName Import-Module
        Mock -CommandName New-AzDoAuthenticationProvider
        Mock -CommandName Invoke-DscLCM
        # exportConfigDir's ValidateScript calls the real Test-Path at parameter-binding time.
        Mock -CommandName Test-Path -MockWith { return $true }

        $exportConfigDir = New-MockDirectoryPath
        $ConfigurationSourcePath = New-MockDirectoryPath

    }

    Context "AzureDevOpsDsc.Common Dependency Check" {

        It "Should throw a clear error if AzureDevOpsDsc.Common cannot be imported" {
            Mock -CommandName Import-Module -MockWith { throw "module not found" }
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*AzureDevOpsDsc.Common*"
            Should -Invoke -CommandName New-AzDoAuthenticationProvider -Exactly 0
            Should -Invoke -CommandName Invoke-DscLCM -Exactly 0
        }

    }

    Context "Execution Logic" {

        BeforeAll {
            function Get-MockPATToken {
                param(
                    [int]$Length = 52
                )

                # Define characters allowed in a PAT token
                $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

                # Generate a random token of specified length
                -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
            }
        }

       It "Should create authentication provider with ManagedIdentity" {
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Assert-MockCalled -CommandName New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter { $useManagedIdentity }
       }

       It "Should create authentication provider with PAT" {
            $PAT = Get-MockPATToken
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken $PAT -AuthenticationType "PAT" -PATToken $PAT -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Assert-MockCalled -CommandName New-AzDoAuthenticationProvider -Exactly 1 -Scope It -ParameterFilter { $PersonalAccessToken -eq $PAT }
       }

    }

    Context "Delegation to Invoke-DscLCM" {

        It "Should delegate to Invoke-DscLCM with the correct parameters" {
            # ParameterFilter binds Invoke-DscLCM's own bound parameters as local variables,
            # which would shadow same-named outer variables — capture expected values under
            # different names first so the comparison isn't a tautology.
            $expectedExportDir = $exportConfigDir
            $expectedSourcePath = $ConfigurationSourcePath

            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Should -Invoke -CommandName Invoke-DscLCM -Exactly 1 -ParameterFilter {
                $exportConfigDir -eq $expectedExportDir -and
                $ConfigurationSourcePath -eq $expectedSourcePath -and
                $ConfigurationMode -eq 'Audit'
            }
        }

        It "Should omit ConfigurationMode from the delegated call when not supplied" {
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationSourcePath $ConfigurationSourcePath
            Should -Invoke -CommandName Invoke-DscLCM -Exactly 1 -ParameterFilter {
                [string]::IsNullOrEmpty($ConfigurationMode)
            }
        }

        It "Should pass through ContinueOnError and ReportPath when supplied" {
            $expectedReportPath = $exportConfigDir
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath -ReportPath $exportConfigDir -ContinueOnError
            Should -Invoke -CommandName Invoke-DscLCM -Exactly 1 -ParameterFilter {
                $ReportPath -eq $expectedReportPath -and $ContinueOnError -eq $true
            }
        }

        It "Should not pass ReportPath or ContinueOnError when not supplied" {
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Should -Invoke -CommandName Invoke-DscLCM -Exactly 1 -ParameterFilter {
                [string]::IsNullOrEmpty($ReportPath) -and $ContinueOnError -ne $true
            }
        }

    }

}
