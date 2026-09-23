
Describe "Protect-SensitiveValue Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        $preParseFilePath = (Get-FunctionPath 'Protect-SensitiveValue.ps1').FullName
        . $preParseFilePath
    }

    Context "Test-SensitivePropertyName" {

        It "flags conventionally-named secrets as sensitive: <Name>" -TestCases @(
            @{ Name = 'Password' }
            @{ Name = 'AdminPassword' }
            @{ Name = 'ApiToken' }
            @{ Name = 'ClientSecret' }
            @{ Name = 'PrivateKey' }
            @{ Name = 'Credential' }
            @{ Name = 'ConnectionString' }
            @{ Name = 'Passphrase' }
        ) {
            param($Name)
            Test-SensitivePropertyName -Name $Name | Should -BeTrue
        }

        It "matches case-insensitively" {
            Test-SensitivePropertyName -Name 'PASSWORD' | Should -BeTrue
            Test-SensitivePropertyName -Name 'password' | Should -BeTrue
        }

        It "does not flag innocuous names: <Name>" -TestCases @(
            @{ Name = 'Ensure' }
            @{ Name = 'ProjectName' }
            @{ Name = 'Visibility' }
        ) {
            param($Name)
            Test-SensitivePropertyName -Name $Name | Should -BeFalse
        }

        It "returns false for an empty string" {
            Test-SensitivePropertyName -Name '' | Should -BeFalse
        }
    }

    Context "Protect-SensitiveValue" {

        It "redacts the value of a sensitive property" {
            Protect-SensitiveValue -Name 'Password' -Value 'hunter2' | Should -Be '[REDACTED]'
        }

        It "returns the value unchanged for a non-sensitive property" {
            Protect-SensitiveValue -Name 'Ensure' -Value 'Present' | Should -Be 'Present'
        }

        It "returns an empty string for a null non-sensitive value" {
            Protect-SensitiveValue -Name 'Ensure' -Value $null | Should -Be ''
        }

        It "still redacts a sensitive property even when the value is null" {
            Protect-SensitiveValue -Name 'Token' -Value $null | Should -Be '[REDACTED]'
        }

        It "stringifies a non-string, non-sensitive value" {
            Protect-SensitiveValue -Name 'Count' -Value 5 | Should -Be '5'
        }
    }
}
