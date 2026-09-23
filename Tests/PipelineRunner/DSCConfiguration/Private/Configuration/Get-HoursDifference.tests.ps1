
Describe "Get-HoursDifference Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Get-HoursDifference.ps1').FullName
        . $preParseFilePath

    }

    Context "When the end time is later than the start time" {

        It "Returns the straightforward hour difference" {
            Get-HoursDifference -StartTime '09:00' -EndTime '17:00' | Should -Be 8
        }

        It "Handles a difference that includes minutes" {
            Get-HoursDifference -StartTime '09:15' -EndTime '10:45' | Should -Be 1.5
        }

        It "Returns zero when start and end are the same" {
            Get-HoursDifference -StartTime '12:00' -EndTime '12:00' | Should -Be 0
        }
    }

    Context "When the end time wraps past midnight" {

        It "Adds 24 hours so the result stays positive" {
            Get-HoursDifference -StartTime '22:00' -EndTime '02:00' | Should -Be 4
        }

        It "Handles a wrap that includes minutes" {
            Get-HoursDifference -StartTime '23:30' -EndTime '00:15' | Should -Be 0.75
        }

        It "Wraps a full day when end equals the minute just before start" {
            $result = Get-HoursDifference -StartTime '00:01' -EndTime '00:00'

            [Math]::Round($result, 4) | Should -Be 23.9833
        }
    }

    Context "When given malformed input" {

        It "Throws when StartTime is not in HH:mm format" {
            { Get-HoursDifference -StartTime 'not-a-time' -EndTime '10:00' } | Should -Throw
        }

        It "Throws when EndTime is not in HH:mm format" {
            { Get-HoursDifference -StartTime '09:00' -EndTime 'not-a-time' } | Should -Throw
        }
    }
}
