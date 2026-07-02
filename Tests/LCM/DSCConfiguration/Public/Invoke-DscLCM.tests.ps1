
Describe "Invoke-DscLCM Function Tests" -Tag Unit {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Invoke-DscLCM.ps1').FullName

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

        # Mock necessary commands to prevent actual execution during tests
        Mock -CommandName Start-LCM
        Mock -CommandName Build-DatumConfiguration
        Mock -CommandName Get-ChildItem -MockWith { @() }
        Mock -CommandName Split-Path -MockWith {
            "$TestDrive\MockPath\"
        }
        Mock -CommandName Test-Path -MockWith { return $true }

        # Invoke-DscLCM always reads and validates datum.yml — mock these globally
        # so unit tests remain focused on Invoke-DscLCM logic rather than datum validation
        Mock -CommandName Get-Content -MockWith { return "MOCKED DATUM CONTENT" }
        Mock -CommandName ConvertFrom-Yaml -MockWith {
            return @{ LCMConfigurationMode = @{ ConfigurationMode = 'Audit'; ChangeWindows = @() } }
        }
        Mock -CommandName Test-DatumConfiguration

        $exportConfigDir = New-MockDirectoryPath
        $ConfigurationSourcePath = New-MockDirectoryPath

    }

    Context "Execution Logic" {

        BeforeAll {
            Mock -CommandName Test-Path -MockWith { return $true }
        }

       It "Should build datum configuration" {
            Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath
            Assert-MockCalled -CommandName Build-DatumConfiguration -Exactly 1 -Scope It
       }
    }

    Context "When testing -ConfigurationSourcePath" {

        it "should call Clone-Repository with a valid URL" {
            Mock -CommandName 'Clone-Repository' -Verifiable -MockWith {
                return '\mockPath'
            }
            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "Audit" -ConfigurationSourcePath "http://mockGitRepo.com/repo"} | Should -Not -Throw
            Should -InvokeVerifiable
        }

        it "should parse a valid file path if it isn't a valid URL" {
            Mock -CommandName 'Clone-Repository'
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $path -eq $exportConfigDir
            } -Verifiable -MockWith { return $true }

            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw
            Should -Invoke 'Clone-Repository' -Exactly 0
            Should -InvokeVerifiable
            Should -Invoke 'Start-LCM' -Exactly 0

        }

        it "should throw an error if it's neither a valid URL or FilePath" {

            Mock -CommandName 'Clone-Repository'
            Mock -CommandName 'Test-Path' -ParameterFilter {
                $path -eq $ConfigurationSourcePath
            } -Verifiable -MockWith { return $false }

            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*Invalid ConfigurationSourcePath*"
            Should -Invoke 'Clone-Repository' -Exactly 0
            Should -InvokeVerifiable
            Should -Invoke 'Start-LCM' -Exactly 0

        }



    }

    Context "When testing -ConfigurationMode" {

        BeforeAll {
            mock -CommandName 'Get-ChildItem' -MockWith { @(
                [PSCustomObject]@{ Fullname = "$TestDrive\mockConfig.yml" }
            ) }
        }

        it "should call Start-LCM with the specified ConfigurationMode" {
            Mock -CommandName 'Start-LCM' -MockWith { return $true } -Verifiable
            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "Audit" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw
            Should -Invoke 'Start-LCM' -Exactly 1 -ParameterFilter {  $ConfigurationMode -eq 'Audit' }
            Should -InvokeVerifiable
        }

        it "should throw an error if an invalid ConfigurationMode is provided" {
            Mock -CommandName 'Start-LCM'
            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationMode "InvalidMode" -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Throw "*Cannot validate argument on parameter 'ConfigurationMode'*"
            Should -Invoke 'Start-LCM' -Exactly 0
        }

        it "should call 'ConvertFrom-Yaml' and 'Get-LCMConfigurationMode' if ConfigurationMode is not provided" {
            Mock -CommandName 'Get-Content' -Verifiable -MockWith { return "MOCKED CONTENT" }
            Mock -CommandName 'ConvertFrom-Yaml' -Verifiable -MockWith { return @{ LCMConfigurationMode = @{ ConfigurationMode = 'Scheduled'; ChangeWindows = @() } } }
            Mock -CommandName 'Get-LCMConfigurationMode' -Verifiable -MockWith { return 'Audit' }
            Mock -CommandName 'Start-LCM' -Verifiable -MockWith { return $true }

            { Invoke-DscLCM -exportConfigDir $exportConfigDir -ConfigurationSourcePath $ConfigurationSourcePath } | Should -Not -Throw

            Should -Invoke 'ConvertFrom-Yaml' -Exactly 1
            Should -Invoke 'Get-LCMConfigurationMode' -Exactly 1
            Should -Invoke 'Start-LCM' -Exactly 1 -ParameterFilter { $ConfigurationMode -eq 'Audit' }

            Should -InvokeVerifiable
        }

    }

}
