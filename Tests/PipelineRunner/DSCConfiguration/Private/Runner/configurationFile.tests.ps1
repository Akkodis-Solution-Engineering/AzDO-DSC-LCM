
Describe "configurationFile Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'configurationFile.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-NormalizedConditionExpression.ps1').FullName
    }

    BeforeEach {
        $script:currentConfigurationFile = $null
    }

    It "returns the configuration file path the runner recorded" {
        $script:currentConfigurationFile = '/configs/SRV-APP-01.yml'
        configurationFile | Should -Be '/configs/SRV-APP-01.yml'
    }

    It "returns `$null outside a run" {
        configurationFile | Should -BeNullOrEmpty
    }

    It "is rewritten from its documented zero-argument spelling into one that parses" {
        ConvertTo-NormalizedConditionExpression -Expression 'configurationFile()' |
            Should -Be '(configurationFile)'
    }

    It "supports member access after the rewrite, e.g. contains(configurationFile(), 'Prod')" {
        $normalized = ConvertTo-NormalizedConditionExpression -Expression "contains (configurationFile()) 'Prod'"
        $normalized | Should -Be "contains ((configurationFile)) 'Prod'"

        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseInput($normalized, [ref] $tokens, [ref] $parseErrors) | Out-Null

        $parseErrors | Should -BeNullOrEmpty
    }
}
