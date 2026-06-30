[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='Variables consumed by dot-sourced Test-DatumConfiguration via PowerShell dynamic scope')]
param()

Describe "Test-DatumConfiguration Function Tests" -Tag Unit, LCM, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Test-DatumConfiguration.ps1').FullName
        
        . $preParseFilePath


        # Mocking Get-Module to return controlled version information
        Mock -CommandName Get-Module -MockWith {
            param($name)
            switch ($name) {
                'PSDesiredStateConfiguration' { @{ Version = [version]"2.0.0" } }
                'azdo-dsc-lcm' { @{ Version = [version]"1.0.0" } }
                default { $null }
            }
        }

        
        Mock -CommandName Write-Warning

    }

    Context "When testing LCMConfigSettings" {

        It "should pass without errors" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion = "1.0.0"
                DSCResourceMaximumVersion = "2.0.0"
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0

        }

        It "should throw an error if LCMConfigSettings is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*LCMConfigSettings*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if version fields are not valid" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "invalid"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*valid version*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if version is outside the valid range" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "3.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw -ErrorId "*outside the valid range*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should issue a warning if two or more minor versions behind" {

            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.8.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion = "1.0.0"
                DSCResourceMaximumVersion = "2.0.0"
            }

            Test-DatumConfiguration -Datum $datumConfig
            Assert-MockCalled Write-Warning -Exactly 1

        }

        it "Should throw an error if outside the valid range" {

            Mock Get-Command 

            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion = "1.0.0"
                DSCResourceMaximumVersion = "2.0.0"
            }

            Test-DatumConfiguration -Datum $datumConfig
            Assert-MockCalled Write-Warning -Exactly 0
        }

    }

    Context "When testing LCMConfigurationMode" {

        BeforeAll {
            $ModuleConfigurationData = @{
                YAMLConfigurationMinimumVersion = "0.9.0"
                YAMLConfigurationMaximumVersion = "2.0.0"
                PSDesiredStateConfigurationMinimumVersion = "1.0.0"
                PSDesiredStateConfigurationMaximumVersion = "2.0.0"
                DSCResourceMinimumVersion = "1.0.0"
                DSCResourceMaximumVersion = "2.0.0"
            }

        }

        It "should pass without errors" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Audit'
                        ChangeWindows = @()
                    }
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0

        }

        It "should throw an error if LCMConfigurationMode is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*LCMConfigurationMode*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if ConfigurationMode is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'InvalidMode'
                        ChangeWindows = @()
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The Datum Configuration LCMConfigurationMode ConfigurationMode property is not one of the allowed values:*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow ConfigurationMode is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "09:00"
                                EndTime = "17:00"
                                ConfigurationMode = 'InvalidMode'
                            }
                        )
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The ConfigurationMode property in each ChangeWindow of the Datum Configuration LCMConfigurationMode must be one of the allowed values*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow is missing required properties" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "09:00"
                                # EndTime is missing
                                ConfigurationMode = 'ApplyOnly'
                            }
                        )
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*Each ChangeWindow in the Datum Configuration LCMConfigurationMode must contain StartTime, EndTime, and ConfigurationMode properties*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        it "should throw an error if ChangeWindow StartTime or EndTime is invalid" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        ConfigurationMode = 'Scheduled'
                        ChangeWindows = @(
                            @{
                                StartTime = "9 AM"  # Invalid format
                                EndTime = "17:00"
                                ConfigurationMode = 'ApplyOnly'
                            }
                        )
                    }                    
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*The StartTime and EndTime properties in the ChangeWindow*"
            Assert-MockCalled Write-Warning -Exactly 0
        }

        It "should throw an error if ConfigurationMode property is missing" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
                        # ConfigurationMode property is missing
                        ChangeWindows = @()
                    }
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }
            { Test-DatumConfiguration -Datum $datumConfig } | Should -Throw "*LCMConfigurationMode*"
            Assert-MockCalled Write-Warning -Exactly 0

        }

        it "should pass when a ChangeWindow includes a valid DaysOfWeek list" {
            $datumConfig = @{
                '__Definition' = @{
                    LCMConfigurationMode = @{
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
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
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
                    LCMConfigurationMode = @{
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
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
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
                    LCMConfigurationMode = @{
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
                    LCMConfigSettings = @{
                        ConfigurationVersion = "1.0.0"
                        AZDOLCMVersion = "1.0.0"
                        DSCResourceVersion = "1.0.0"
                    }
                }
            }

            { Test-DatumConfiguration -Datum $datumConfig } | Should -Not -Throw
            Assert-MockCalled Write-Warning -Exactly 0
        }

    }
}
