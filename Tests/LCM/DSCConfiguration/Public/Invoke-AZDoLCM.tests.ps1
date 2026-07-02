
Describe "Invoke-AZDoLCM Function Tests" -Tag Unit {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Invoke-AZDoLCM.ps1').FullName

        @(
            (Get-FunctionPath 'Start-LCM.ps1')
            (Get-FunctionPath 'Build-DatumConfiguration.ps1')
            (Get-FunctionPath 'Clone-Repository.ps1')
            (Get-FunctionPath 'Get-LCMConfigurationMode.ps1')
            (Get-FunctionPath 'Test-DatumConfiguration.ps1')
        ) | ForEach-Object {
            . $_.FullName
        }

        . $preParseFilePath

        # Mock Authentication Provider Function
        Function New-AzDoAuthenticationProvider {
            param($OrganizationName, $PersonalAccessToken, [switch]$useManagedIdentity)
        }


        # Mock necessary commands to prevent actual execution during tests
        Mock -CommandName Get-DSCResource -MockWith { @{ Version = @{ Major = 2 } } }
        Mock -CommandName Get-Module -MockWith { @{ Name = 'AzureDevOpsDsc' } }
        Mock -CommandName Import-Module
        Mock -CommandName New-AzDoAuthenticationProvider
        Mock -CommandName Start-LCM
        Mock -CommandName Build-DatumConfiguration
        Mock -CommandName Get-ChildItem -MockWith { @() }
        Mock -CommandName Split-Path -MockWith {
            "$TestDrive\MockPath\"
        }
        Mock -CommandName Test-Path -MockWith { return $true }

        # Invoke-AZDoLCM now always reads and validates datum.yml — mock these globally
        # so unit tests remain focused on Invoke-AZDoLCM logic rather than datum validation
        Mock -CommandName Get-Content -MockWith { return "MOCKED DATUM CONTENT" }
        Mock -CommandName ConvertFrom-Yaml -MockWith {
            return @{ LCMConfigurationMode = @{ ConfigurationMode = 'Audit'; ChangeWindows = @() } }
        }
        Mock -CommandName Test-DatumConfiguration

        $exportConfigDir = New-MockDirectoryPath
        $ConfigurationSourcePath = New-MockDirectoryPath

    }

    Context "Environment Variable Check" {

            BeforeAll {
                Mock -CommandName Test-Path -MockWith { return $true }
                $Env:AZDODSC_CACHE_DIRECTORY = $null
            }

            AfterAll {
                $Env:AZDODSC_CACHE_DIRECTORY = $null
            }

        It "Should throw an error if AZDODSC_CACHE_DIRECTORY environment variable is not set" {
            Remove-Item Env:AZDODSC_CACHE_DIRECTORY -ErrorAction SilentlyContinue
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*The Environment Variable AZDODSC_CACHE_DIRECTORY is not set. Please set the environment variable before running this script*"
        }

        It "Should not throw an error if AZDODSC_CACHE_DIRECTORY environment variable is set" {
            $env:AZDODSC_CACHE_DIRECTORY = "SomePath"
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw
        } 
    }

    Context "Execution Logic" {

        BeforeAll {
            Mock -CommandName Test-Path -MockWith { return $true }
            $Env:AZDODSC_CACHE_DIRECTORY = "mocked"

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

       It "Should build datum configuration" {
            Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Assert-MockCalled -CommandName Build-DatumConfiguration -Exactly 1 -Scope It
       }
    }

    Context "When testing -ConfigurationSourcePath" {

        BeforeAll {
            $Env:AZDODSC_CACHE_DIRECTORY = "mocked"
        }

        AfterAll {
            $Env:AZDODSC_CACHE_DIRECTORY = $null
        }

        it "should call Clone-Repository with a valid URL" {
            Mock -CommandName 'Clone-Repository' -Verifiable -MockWith {
                return '\mockPath'
            }
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath "http://mockGitRepo.com/repo"} | Should -Not -Throw
            Should -InvokeVerifiable
        }

        it "should parse a valid file path if it isn't a valid URL" {
            Mock -CommandName 'Clone-Repository'
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $path -eq $exportConfigDir
            } -Verifiable -MockWith { return $true }

            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw
            Should -Invoke 'Clone-Repository' -Exactly 0
            Should -InvokeVerifiable
            Should -Invoke 'Start-LCM' -Exactly 0

        }

        it "should throw an error if it's neither a valid URL or FilePath" {

            Mock -CommandName 'Clone-Repository'
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $path -eq $ConfigurationSourcePath
            } -Verifiable -MockWith { return $false }

            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*Invalid ConfigurationSourcePath*"
            Should -Invoke 'Clone-Repository' -Exactly 0
            Should -InvokeVerifiable
            Should -Invoke 'Start-LCM' -Exactly 0            

        }



    }

    Context "When testing -ConfigurationMode" {

        BeforeAll {
            $Env:AZDODSC_CACHE_DIRECTORY = "mocked"
            mock -CommandName 'Get-ChildItem' -MockWith { @(
                [PSCustomObject]@{ Fullname = "$TestDrive\mockConfig.yml" }
            ) }
        }

        AfterAll {
            $Env:AZDODSC_CACHE_DIRECTORY = $null
        }

        it "should call Start-LCM with the specified ConfigurationMode" {
            Mock -CommandName 'Start-LCM' -MockWith { return $true } -Verifiable
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw
            Should -Invoke 'Start-LCM' -Exactly 1 -ParameterFilter {  $ConfigurationMode -eq 'Audit' }
            Should -InvokeVerifiable
        }

        it "should throw an error if an invalid ConfigurationMode is provided" {
            Mock -CommandName 'Start-LCM'
            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationMode "InvalidMode" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*Cannot validate argument on parameter 'ConfigurationMode'*"
            Should -Invoke 'Start-LCM' -Exactly 0
        }

        it "should call 'ConvertFrom-Yaml' and 'Get-LCMConfigurationMode' if ConfigurationMode is not provided" {
            Mock -CommandName 'Get-Content' -Verifiable -MockWith { return "MOCKED CONTENT" }
            Mock -CommandName 'ConvertFrom-Yaml' -Verifiable -MockWith { return @{ LCMConfigurationMode = @{ ConfigurationMode = 'Scheduled'; ChangeWindows = @() } } }
            Mock -CommandName 'Get-LCMConfigurationMode' -Verifiable -MockWith { return 'Audit' }
            Mock -CommandName 'Start-LCM' -Verifiable -MockWith { return $true }

            { Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir $exportConfigDir -JITToken "abc123" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw

            Should -Invoke 'ConvertFrom-Yaml' -Exactly 1
            Should -Invoke 'Get-LCMConfigurationMode' -Exactly 1
            Should -Invoke 'Start-LCM' -Exactly 1 -ParameterFilter { $ConfigurationMode -eq 'Audit' }

            Should -InvokeVerifiable
        }

    }

}
