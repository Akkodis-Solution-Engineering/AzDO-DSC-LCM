Describe "Get-LCMConfigurationMode Function Tests" -Tag Unit, LCM, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Get-LCMConfigurationMode.ps1').FullName

        . $preParseFilePath

    }

    Context "When the top-level ConfigurationMode is 'ApplyOnly', 'Audit', or 'Enforce'" {

        BeforeAll {
            $DatumConfigurationMode = @{
                ConfigurationMode = 'ApplyOnly'
            }
        }

        It "should return the ConfigurationMode as ApplyOnly" {
            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'ApplyOnly'
        }

        It "should return the ConfigurationMode as Audit" {
            $DatumConfigurationMode.ConfigurationMode = 'Audit'
            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Audit'
        }

        It "should return the ConfigurationMode as Enforce" {
            $DatumConfigurationMode.ConfigurationMode = 'Enforce'
            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Enforce'
        }

    }

    Context "When the top-level ConfigurationMode is 'Scheduled'" {

        BeforeAll {
            $DatumConfigurationMode = @{
                ConfigurationMode = 'Scheduled'
                ChangeWindows = @(
                    @{
                        StartTime = '20:00'
                        EndTime = '24:00'
                        ConfigurationMode = 'Audit'
                    },
                    @{
                        StartTime = '00:00'
                        EndTime = '02:00'
                        ConfigurationMode = 'Enforce'
                    }
                )
            }
        }

        It "should return the correct ConfigurationMode based on current time within the first ChangeWindow" {
            # Mock Get-Date to return a time within the first ChangeWindow
            Mock -CommandName Get-Date -MockWith { 
                return [DateTime]::ParseExact("2023-01-01T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Audit'
        }

        It "should return the correct ConfigurationMode based on current time within the second ChangeWindow" {
            # Mock Get-Date to return a time within the second ChangeWindow
            Mock -CommandName Get-Date -MockWith { 
                return [DateTime]::ParseExact("2023-01-01T01:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Enforce'
        }

        It "should default to Audit when current time is outside all ChangeWindows" {
            # Mock Get-Date to return a time outside all ChangeWindows
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-01T15:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Audit'
        }

    }

}