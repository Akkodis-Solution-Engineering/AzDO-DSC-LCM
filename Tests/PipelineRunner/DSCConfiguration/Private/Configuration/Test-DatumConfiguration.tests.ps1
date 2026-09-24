[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='Variables consumed by dot-sourced Test-DatumConfiguration via PowerShell dynamic scope')]
param()

Describe "Test-DatumConfiguration Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Test-DatumConfiguration.ps1').FullName
        
        . $preParseFilePath


        # Mocking Get-Module to return controlled version information
        Mock -CommandName Get-Module -MockWith {
            param($name)
            switch ($name) {
                'PSDesiredStateConfiguration' { @{ Version = [version]"2.0.0" } }
                'DSC.PipelineRunner.Akkodis' { @{ Version = [version]"1.0.0" } }
                default { $null }
            }
        }

        
        Mock -CommandName Write-Warning

    }

    Context "When testing PipelineRunnerSettings" {

        It "should pass without errors" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.9.0"
                YAMLConfigurationMaximumVersion           = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion                 = "1.0.0"
                DSCResourceMaximumVersion                 = "2.0.0"
                PipelineRunnerMinimumVersion                     = "0.1.0"
                PipelineRunnerMaximumVersion                     = "1.9.0"
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0

        }

        It "should throw an error if PipelineRunnerSettings is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*PipelineRunnerSettings*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if version fields are not valid" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "invalid"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.9.0"
                YAMLConfigurationMaximumVersion           = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion                 = "1.0.0"
                DSCResourceMaximumVersion                 = "2.0.0"
                PipelineRunnerMinimumVersion                     = "0.1.0"
                PipelineRunnerMaximumVersion                     = "1.9.0"
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*valid version*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if version is outside the valid range" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "3.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.9.0"
                YAMLConfigurationMaximumVersion           = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion                 = "1.0.0"
                DSCResourceMaximumVersion                 = "2.0.0"
                PipelineRunnerMinimumVersion                     = "0.1.0"
                PipelineRunnerMaximumVersion                     = "1.9.0"
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*outside the valid range*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should issue a warning if two or more minor versions behind YAMLConfigurationCurrentVersion" {

            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{ ConfigurationMode = 'Audit' }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "0.3"
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.1"
                YAMLConfigurationMaximumVersion           = "0.9"
                YAMLConfigurationCurrentVersion           = "0.5"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                PipelineRunnerMinimumVersion              = "0.1.0"
                PipelineRunnerMaximumVersion              = "1.9.0"
            }

            Test-DatumConfiguration -Datum $datumConfig
            Assert-MockCalled Write-Warning -Exactly 1 -ParameterFilter { $Message -like '*two or more minor versions behind*' }

        }

        It "should not warn when the configuration is at or one behind YAMLConfigurationCurrentVersion" -TestCases @(
            @{ Version = '0.5' }, @{ Version = '0.4' }, @{ Version = '0.9' }
        ) {
            param($Version)

            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{ ConfigurationMode = 'Audit' }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = $Version
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.1"
                YAMLConfigurationMaximumVersion           = "0.9"
                YAMLConfigurationCurrentVersion           = "0.5"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                PipelineRunnerMinimumVersion              = "0.1.0"
                PipelineRunnerMaximumVersion              = "1.9.0"
            }

            Test-DatumConfiguration -Datum $datumConfig
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should reject 0.10 when the maximum is 0.9 (versions are not compared as decimals)" {

            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{ ConfigurationMode = 'Audit' }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "0.10"
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.1"
                YAMLConfigurationMaximumVersion           = "0.9"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                PipelineRunnerMinimumVersion              = "0.1.0"
                PipelineRunnerMaximumVersion              = "1.9.0"
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*outside the valid range*"
        }

        it "Should throw an error if outside the valid range" {

            Mock Get-Command 

            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.9.0"
                YAMLConfigurationMaximumVersion           = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion                 = "1.0.0"
                DSCResourceMaximumVersion                 = "2.0.0"
                PipelineRunnerMinimumVersion                     = "0.1.0"
                PipelineRunnerMaximumVersion                     = "1.9.0"
            }

            Test-DatumConfiguration -Datum $datumConfig
            Assert-MockCalled Write-Warning -Exactly 0
        }

    }

    Context "When testing the DSC.PipelineRunner.Akkodis version bounds" {

        BeforeAll {
            $script:RunnerDatum = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "0.5"
                        PipelineRunnerVersion = "0.0.5"
                    }
                }
            }
        }

        It "should check the installed runner against PipelineRunner*, not DSCResource*, bounds" {
            Mock -CommandName Get-Module -MockWith {
                param($name)
                switch ($name) {
                    'PSDesiredStateConfiguration' { @{ Version = [version]"2.0.0" } }
                    'DSC.PipelineRunner.Akkodis' { @{ Version = [version]"0.0.5" } }
                    default { $null }
                }
            }

            # 0.0.5 is below the DSCResource bounds but inside the PipelineRunner bounds.
            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.1"
                YAMLConfigurationMaximumVersion           = "0.9"
                PSDesiredStateConfigurationMinimumVersion = "2.0"
                PSDesiredStateConfigurationMaximumVersion = "2.9"
                DSCResourceMinimumVersion                 = "1.0"
                DSCResourceMaximumVersion                 = "1.9"
                PipelineRunnerMinimumVersion              = "0.0.1"
                PipelineRunnerMaximumVersion              = "1.9"
            }

            { Test-DatumConfiguration -Datum $script:RunnerDatum } | Should -Not -Throw
        }

        It "should throw when the installed runner is below PipelineRunnerMinimumVersion" {
            Mock -CommandName Get-Module -MockWith {
                param($name)
                switch ($name) {
                    'PSDesiredStateConfiguration' { @{ Version = [version]"2.0.0" } }
                    'DSC.PipelineRunner.Akkodis' { @{ Version = [version]"0.0.5" } }
                    default { $null }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.1"
                YAMLConfigurationMaximumVersion           = "0.9"
                PSDesiredStateConfigurationMinimumVersion = "2.0"
                PSDesiredStateConfigurationMaximumVersion = "2.9"
                DSCResourceMinimumVersion                 = "0.0.1"
                DSCResourceMaximumVersion                 = "1.9"
                PipelineRunnerMinimumVersion              = "0.1"
                PipelineRunnerMaximumVersion              = "1.9"
            }

            { Test-DatumConfiguration -Datum $script:RunnerDatum } | Should -Throw -ExpectedMessage "*DSC.PipelineRunner.Akkodis Version 0.0.5 is outside the valid range*"
        }

        It "should accept the shipped Example Configuration with the shipped bounds and manifest version" {
            # The repository's Example Configuration is the reference configuration, so it must
            # pass validation against the bounds and module version that actually ship.
            . (Get-FunctionPath 'VersionConfiguration.ps1').FullName
            $shippedBounds = $ModuleConfigurationData

            $manifestPath = Join-Path $Global:RepositoryRoot 'source/DSC.PipelineRunner.Akkodis.psd1'
            $script:ManifestVersion = [version](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion

            Mock -CommandName Get-Module -MockWith {
                param($name)
                switch ($name) {
                    'PSDesiredStateConfiguration' { @{ Version = [version]"2.0.0" } }
                    'DSC.PipelineRunner.Akkodis' { @{ Version = $script:ManifestVersion } }
                    default { $null }
                }
            }

            $exampleDatumPath = Join-Path $Global:RepositoryRoot 'Example Configuration/Datum.yml'
            $exampleDefinition = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $exampleDatumPath -Raw)
            $datumConfig = @{ '__Definition' = $exampleDefinition }

            $ModuleConfigurationData = $shippedBounds

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
        }
    }

    Context "When testing PipelineConfigurationMode" {

        BeforeAll {
            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion           = "0.9.0"
                YAMLConfigurationMaximumVersion           = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion                 = "1.0.0"
                DSCResourceMaximumVersion                 = "2.0.0"
                PipelineRunnerMinimumVersion                     = "0.1.0"
                PipelineRunnerMaximumVersion                     = "1.9.0"
            }
        }

        It "should pass without errors" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0

        }

        It "should throw an error if PipelineConfigurationMode is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*PipelineConfigurationMode*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if ConfigurationMode is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'InvalidMode'
                        ChangeWindows = @()
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The Datum Configuration PipelineConfigurationMode ConfigurationMode property is not one of the allowed values:*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow ConfigurationMode is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "09:00"
                                EndTime = "17:00"
                                ConfigurationMode = 'InvalidMode'
                            }
                        )
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The ConfigurationMode property in each ChangeWindow of the Datum Configuration PipelineConfigurationMode must be one of the allowed values*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow is missing required properties" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "09:00"
                                # EndTime is missing
                                ConfigurationMode = 'ApplyOnly'
                            }
                        )
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*Each ChangeWindow in the Datum Configuration PipelineConfigurationMode must contain StartTime, EndTime, and ConfigurationMode properties*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow StartTime or EndTime is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "9 AM"  # Invalid format
                                EndTime = "17:00"
                                ConfigurationMode = 'ApplyOnly'
                            }
                        )
                    }                    
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The StartTime and EndTime properties in the ChangeWindow*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should not require ChangeWindows when the ConfigurationMode is not Scheduled" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = [ordered]@{ ConfigurationMode = 'Enforce' }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
        }

        It "should require ChangeWindows when the ConfigurationMode is Scheduled" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = [ordered]@{ ConfigurationMode = 'Scheduled' }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*ChangeWindows property, which is required*"
        }

        It "should throw an error if ConfigurationMode property is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        # ConfigurationMode property is missing
                        ChangeWindows = @()
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*PipelineConfigurationMode*"
            Assert-MockCalled Write-Warning -Exactly 0

        }

        it "should pass when a ChangeWindow includes a valid DaysOfWeek list" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime         = "20:00"
                                EndTime           = "23:59"
                                ConfigurationMode = 'Enforce'
                                DaysOfWeek        = @('Tuesday', 'Wednesday', 'Thursday')
                            }
                        )
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error when a ChangeWindow DaysOfWeek contains an invalid day name" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime         = "20:00"
                                EndTime           = "23:59"
                                ConfigurationMode = 'Enforce'
                                DaysOfWeek        = @('Tuesday', 'Funday')  # 'Funday' is not valid
                            }
                        )
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*Invalid DaysOfWeek value 'Funday'*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should pass when DaysOfWeek is absent from a ChangeWindow" {
            $datumConfig = @{
                '__Definition' = @{
                    PipelineConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime         = "20:00"
                                EndTime           = "23:59"
                                ConfigurationMode = 'Audit'
                                # No DaysOfWeek — optional property
                            }
                        )
                    }
                    PipelineRunnerSettings = @{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should accept ordered dictionaries, which is what Datum returns for Datum.yml" {
            # OrderedDictionary has no ContainsKey(); every other test here uses plain hashtables,
            # which is how a ContainsKey() call once passed unit tests and failed every real run.
            $datumConfig = @{
                '__Definition' = [ordered]@{
                    PipelineConfigurationMode = [ordered]@{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            [ordered]@{
                                StartTime         = "20:00"
                                EndTime           = "23:59"
                                ConfigurationMode = 'Audit'
                            }
                        )
                    }
                    PipelineRunnerSettings = [ordered]@{
                        ConfigurationVersion = "1.0.0"
                        PipelineRunnerVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
        }

    }
}
