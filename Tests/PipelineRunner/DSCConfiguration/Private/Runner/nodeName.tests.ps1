
Describe "nodeName Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'nodeName.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-NormalizedConditionExpression.ps1').FullName
    }

    BeforeEach {
        $script:currentNodeName = $null
    }

    It "returns the node name the runner recorded" {
        $script:currentNodeName = 'SRV-APP-01'
        nodeName | Should -Be 'SRV-APP-01'
    }

    It "returns `$null outside a run" {
        nodeName | Should -BeNullOrEmpty
    }

    It "is rewritten from its documented zero-argument spelling into one that parses" {
        # `identifier()` is not valid PowerShell, so the documented nodeName() spelling only
        # works because the normalizer rewrites it before the condition is parsed.
        ConvertTo-NormalizedConditionExpression -Expression "startsWith (nodeName()) 'SRV'" |
            Should -Be "startsWith ((nodeName)) 'SRV'"
    }

    It "produces a rewritten condition that actually parses" {
        $normalized = ConvertTo-NormalizedConditionExpression -Expression "startsWith (nodeName()) 'SRV'"

        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseInput($normalized, [ref] $tokens, [ref] $parseErrors) | Out-Null

        $parseErrors | Should -BeNullOrEmpty
    }
}
