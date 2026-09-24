Describe "SetVariables Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {
         # Load the functions to test
         $preParseFilePath = (Get-FunctionPath 'SetVariables.ps1').FullName
         $reservedFilePath = (Get-FunctionPath 'Test-RunnerReservedVariableName.ps1').FullName

         . $preParseFilePath
         . $reservedFilePath
    }

    BeforeEach {
        # Initialize empty target hashtable
        $global:target = @{}
        $script:runnerScriptVariableNames = $null
        $script:runnerEnvironmentVariableNames = $null
    }

    It "should create script-level variables with underscores replacing dots" {
        $source = @{
            "Key.With.Dot" = "DotValue"
        }

        SetVariables -Source $source -Target $global:target

        $script:Key_With_Dot | Should -Be "DotValue"
    }

    It "should add every key to the target hashtable" {
        SetVariables -Source @{ EnvVar = 'Value' } -Target $global:target

        $global:target['EnvVar'] | Should -Be 'Value'
    }

    It "should overwrite an existing key in the target instead of throwing" {
        $global:target['EnvVar'] = 'Old'

        { SetVariables -Source @{ EnvVar = 'New' } -Target $global:target } | Should -Not -Throw
        $global:target['EnvVar'] | Should -Be 'New'
    }

    It "should create an environment variable the runner owns and update it on the next call" {
        SetVariables -Source @{ EnvVar = 'First' } -Target $global:target
        $env:EnvVar | Should -Be 'First'

        SetVariables -Source @{ EnvVar = 'Second' } -Target @{}
        $env:EnvVar | Should -Be 'Second'
    }

    It "should not overwrite an environment variable that existed before the runner" {
        Mock Write-Warning
        $env:EnvVar = 'FromTheHost'

        SetVariables -Source @{ EnvVar = 'FromConfig' } -Target $global:target

        $env:EnvVar | Should -Be 'FromTheHost'
        $global:target['EnvVar'] | Should -Be 'FromConfig'
        Should -Invoke Write-Warning -ParameterFilter { $Message -like "*Environment variable 'EnvVar' already exists*" }
    }

    It "should not replace a preference variable" {
        Mock Write-Warning
        $before = $ErrorActionPreference

        SetVariables -Source @{ ErrorActionPreference = 'Ignore' } -Target $global:target

        $ErrorActionPreference | Should -Be $before
        $global:target['ErrorActionPreference'] | Should -Be 'Ignore'
        Should -Invoke Write-Warning -ParameterFilter { $Message -like "*shares its name*" }
    }

    It "should not replace a script variable the runner did not create" {
        Mock Write-Warning
        $script:RunnerOwnedState = 'keep'

        SetVariables -Source @{ RunnerOwnedState = 'clobber' } -Target $global:target

        $script:RunnerOwnedState | Should -Be 'keep'
        Remove-Variable -Name RunnerOwnedState -Scope Script
    }

    AfterEach {
        # Clean up environment variables and script variables
        Remove-Item -Path env:EnvVar -ErrorAction SilentlyContinue
        Remove-Item -Path env:ErrorActionPreference -ErrorAction SilentlyContinue
        Remove-Item -Path env:RunnerOwnedState -ErrorAction SilentlyContinue
        Remove-Item -Path env:Key_With_Dot -ErrorAction SilentlyContinue
        Remove-Variable -Name Key_With_Dot -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name EnvVar -Scope Script -ErrorAction SilentlyContinue
    }
}
