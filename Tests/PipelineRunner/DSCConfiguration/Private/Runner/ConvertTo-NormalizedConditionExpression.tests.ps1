
Describe "ConvertTo-NormalizedConditionExpression Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'ConvertTo-NormalizedConditionExpression.ps1').FullName
    }

    It "rewrites a bare result() call to (result)" {
        ConvertTo-NormalizedConditionExpression -Expression 'result()' | Should -Be '(result)'
    }

    It "rewrites result() with member access, keeping the member access intact" {
        ConvertTo-NormalizedConditionExpression -Expression 'result().InDesiredState' |
            Should -Be '(result).InDesiredState'
    }

    It "rewrites stopProcessing()" {
        ConvertTo-NormalizedConditionExpression -Expression 'stopProcessing()' | Should -Be '(stopProcessing)'
    }

    It "rewrites nodeName()" {
        ConvertTo-NormalizedConditionExpression -Expression 'nodeName()' | Should -Be '(nodeName)'
    }

    It "rewrites configurationFile()" {
        ConvertTo-NormalizedConditionExpression -Expression 'configurationFile()' | Should -Be '(configurationFile)'
    }

    It "rewrites a zero-argument accessor nested inside another call" {
        ConvertTo-NormalizedConditionExpression -Expression "startsWith (nodeName()) 'SRV'" |
            Should -Be "startsWith ((nodeName)) 'SRV'"
    }

    It "rewrites the documented 'fail or stop' composition" {
        ConvertTo-NormalizedConditionExpression -Expression 'result().InDesiredState -or stopProcessing()' |
            Should -Be '(result).InDesiredState -or (stopProcessing)'
    }

    It "rewrites every occurrence when the same accessor appears more than once" {
        ConvertTo-NormalizedConditionExpression -Expression 'equals (nodeName()) (nodeName())' |
            Should -Be 'equals ((nodeName)) ((nodeName))'
    }

    It "leaves an expression with no zero-argument accessors unchanged" {
        ConvertTo-NormalizedConditionExpression -Expression "equals (variables 'Env') 'Prod'" |
            Should -Be "equals (variables 'Env') 'Prod'"
    }

    It "does not touch an accessor called with an argument, e.g. variables('X')" {
        # Guards against an over-eager regex: 'variables' is not one of the four zero-argument
        # accessors, so a call that takes an argument must never be rewritten.
        ConvertTo-NormalizedConditionExpression -Expression "variables('X')" |
            Should -Be "variables('X')"
    }

    It "does not rewrite a substring match inside a longer identifier" {
        # The rewrite is word-boundary anchored (\b...\(\)), so an unrelated identifier that
        # happens to end with one of the four accessor names must not be mangled.
        ConvertTo-NormalizedConditionExpression -Expression 'myNodeName()' | Should -Be 'myNodeName()'
    }

    It "returns an empty string unchanged" {
        ConvertTo-NormalizedConditionExpression -Expression '' | Should -Be ''
    }

    It "produces text that actually parses" {
        $normalized = ConvertTo-NormalizedConditionExpression -Expression 'result().InDesiredState -or stopProcessing()'

        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($normalized, [ref]$tokens, [ref]$parseErrors) | Out-Null

        $parseErrors | Should -BeNullOrEmpty
    }
}
