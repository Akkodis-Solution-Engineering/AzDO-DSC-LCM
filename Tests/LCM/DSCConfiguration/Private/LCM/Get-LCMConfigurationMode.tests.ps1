Describe "Get-LCMConfigurationMode Function Tests" -Tag Unit, LCM, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Get-LCMConfigurationMode.ps1').FullName

        . $preParseFilePath

        Mock -CommandName Write-Host

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

    Context "When ChangeWindows include a DaysOfWeek constraint" {

        BeforeAll {
            # 2023-01-03 is a Tuesday, 21:00 UTC
            $DatumConfigurationMode = @{
                ConfigurationMode = 'Scheduled'
                ChangeWindows = @(
                    @{
                        StartTime         = '20:00'
                        EndTime           = '23:59'
                        ConfigurationMode = 'Enforce'
                        DaysOfWeek        = @('Tuesday', 'Wednesday', 'Thursday')
                    },
                    @{
                        StartTime         = '20:00'
                        EndTime           = '23:59'
                        ConfigurationMode = 'Audit'
                        # No DaysOfWeek — matches every day
                    }
                )
            }
        }

        It "should match a window when the current day is in DaysOfWeek" {
            # Tuesday 21:00 UTC
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-03T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            $result | Should -Be 'Enforce'
        }

        It "should skip a window when the current day is NOT in DaysOfWeek and fall through to the next match" {
            # Sunday 21:00 UTC — not in Tuesday/Wednesday/Thursday
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-01T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfigurationMode
            # First window skipped (Sunday not in DaysOfWeek); second window has no DaysOfWeek → matches
            $result | Should -Be 'Audit'
        }

        It "should default to Audit when time matches but no window's DaysOfWeek includes the current day" {
            $dayOnlyConfig = @{
                ConfigurationMode = 'Scheduled'
                ChangeWindows = @(
                    @{
                        StartTime         = '20:00'
                        EndTime           = '23:59'
                        ConfigurationMode = 'Enforce'
                        DaysOfWeek        = @('Monday')
                    }
                )
            }

            # Sunday 21:00 UTC
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-01T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $dayOnlyConfig
            $result | Should -Be 'Audit'
        }

        It "should match a window with no DaysOfWeek constraint on any day" {
            $noDayConfig = @{
                ConfigurationMode = 'Scheduled'
                ChangeWindows = @(
                    @{
                        StartTime         = '20:00'
                        EndTime           = '23:59'
                        ConfigurationMode = 'Enforce'
                        # No DaysOfWeek
                    }
                )
            }

            # Sunday 21:00 UTC
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-01T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $noDayConfig
            $result | Should -Be 'Enforce'
        }

        It "should match DaysOfWeek case-insensitively" {
            $mixedCaseConfig = @{
                ConfigurationMode = 'Scheduled'
                ChangeWindows = @(
                    @{
                        StartTime         = '20:00'
                        EndTime           = '23:59'
                        ConfigurationMode = 'Enforce'
                        DaysOfWeek        = @('tuesday')  # lower-case
                    }
                )
            }

            # Tuesday 21:00 UTC
            Mock -CommandName Get-Date -MockWith {
                return [DateTime]::ParseExact("2023-01-03T21:00:00Z", "yyyy-MM-ddTHH:mm:ssZ", $null)
            }

            $result = Get-LCMConfigurationMode -DatumConfigurationMode $mixedCaseConfig
            $result | Should -Be 'Enforce'
        }

    }

}