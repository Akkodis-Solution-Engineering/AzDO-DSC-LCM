Describe "Environment Function Tests" -Tag Unit, PipelineRunner, Credential {

    BeforeAll {
        $script:EnvironmentPath = (Get-FunctionPath 'Environment.ps1').FullName
    }

    AfterEach {
        Remove-Item Env:\DscPipelineRunnerTestUser -ErrorAction SilentlyContinue
        Remove-Item Env:\DscPipelineRunnerTestPass -ErrorAction SilentlyContinue
    }

    It "Throws when UserNameVariable or PasswordVariable is missing from the context" {
        { & $script:EnvironmentPath -Context @{} } | Should -Throw "*required*"
        { & $script:EnvironmentPath -Context @{ UserNameVariable = 'X' } } | Should -Throw "*required*"
        { & $script:EnvironmentPath -Context @{ PasswordVariable = 'Y' } } | Should -Throw "*required*"
    }

    It "Throws when the named environment variables are not set" {
        { & $script:EnvironmentPath -Context @{ UserNameVariable = 'DscPipelineRunnerTestUser'; PasswordVariable = 'DscPipelineRunnerTestPass' } } |
            Should -Throw "*not set*"
    }

    It "Builds a PSCredential from the named environment variables" {
        $env:DscPipelineRunnerTestUser = 'svc-account'
        $env:DscPipelineRunnerTestPass = 'super-secret'

        $result = & $script:EnvironmentPath -Context @{ UserNameVariable = 'DscPipelineRunnerTestUser'; PasswordVariable = 'DscPipelineRunnerTestPass' }

        $result | Should -BeOfType ([System.Management.Automation.PSCredential])
        $result.UserName | Should -Be 'svc-account'
        $result.GetNetworkCredential().Password | Should -Be 'super-secret'
    }

    It "Throws when only the username variable resolves and the password variable is unset" {
        $env:DscPipelineRunnerTestUser = 'svc-account'

        { & $script:EnvironmentPath -Context @{ UserNameVariable = 'DscPipelineRunnerTestUser'; PasswordVariable = 'DscPipelineRunnerTestPass' } } |
            Should -Throw "*not set*"
    }
}
