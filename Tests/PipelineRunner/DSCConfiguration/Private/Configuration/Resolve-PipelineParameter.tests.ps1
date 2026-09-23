
Describe "Resolve-PipelineParameter Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Resolve-PipelineParameter.ps1').FullName
        . $preParseFilePath

    }

    AfterEach {
        $script:parameters = $null
    }

    Context "When the parameter table is populated" {

        It "Resolves a defined parameter's value" {
            $script:parameters = @{ Environment = 'Production' }

            Resolve-PipelineParameter -Name 'Environment' | Should -Be 'Production'
        }

        It "Resolves a parameter that is legitimately an empty string" {
            # Presence is tested with a key lookup, not the value, so a declared empty
            # string parameter must resolve to '' rather than be reported as missing.
            $script:parameters = @{ Suffix = '' }

            Resolve-PipelineParameter -Name 'Suffix' | Should -Be ''
        }

        It "Resolves a parameter from an ordered dictionary (as a JSON-loaded configuration produces)" {
            $ordered = [System.Management.Automation.OrderedHashtable]::new()
            $ordered['Environment'] = 'Staging'
            $script:parameters = $ordered

            Resolve-PipelineParameter -Name 'Environment' | Should -Be 'Staging'
        }

        It "Throws a terminating error naming the parameter when it is not defined" {
            $script:parameters = @{ Environment = 'Production' }

            { Resolve-PipelineParameter -Name 'DoesNotExist' } | Should -Throw -ExpectedMessage "*'DoesNotExist'*"
        }
    }

    Context "When the parameter table is not populated" {

        It "Throws when the parameters table is `$null" {
            $script:parameters = $null

            { Resolve-PipelineParameter -Name 'Environment' } | Should -Throw
        }

        It "Throws when the parameters table is not a dictionary" {
            $script:parameters = 'not-a-dictionary'

            { Resolve-PipelineParameter -Name 'Environment' } | Should -Throw
        }
    }
}
