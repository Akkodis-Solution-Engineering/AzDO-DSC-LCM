
Describe "ConvertTo-ConditionNumber Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'ConvertTo-ConditionNumber.ps1').FullName
    }

    Context "already-numeric operands preserve their own integrality" {

        It "returns an [int] operand as [long]" {
            $result = ConvertTo-ConditionNumber -Value 7 -Accessor 'add'
            $result | Should -Be 7
            $result | Should -BeOfType [long]
        }

        It "returns a [long] operand as [long]" {
            $result = ConvertTo-ConditionNumber -Value ([long]42) -Accessor 'add'
            $result | Should -BeOfType [long]
        }

        It "returns a [double] operand as [double]" {
            $result = ConvertTo-ConditionNumber -Value 2.5 -Accessor 'mul'
            $result | Should -Be 2.5
            $result | Should -BeOfType [double]
        }

        It "does not collapse a whole-number [double] to [long]" {
            $result = ConvertTo-ConditionNumber -Value ([double]7.0) -Accessor 'div'
            $result | Should -Be 7.0
            $result | Should -BeOfType [double]
        }
    }

    Context "string operands are parsed with the invariant culture" {

        It "parses an integer string as [long]" {
            $result = ConvertTo-ConditionNumber -Value '7' -Accessor 'add'
            $result | Should -Be 7
            $result | Should -BeOfType [long]
        }

        It "parses a decimal string as [double]" {
            $result = ConvertTo-ConditionNumber -Value '7.5' -Accessor 'add'
            $result | Should -Be 7.5
            $result | Should -BeOfType [double]
        }

        It "parses a negative integer string as [long]" {
            $result = ConvertTo-ConditionNumber -Value '-3' -Accessor 'sub'
            $result | Should -Be -3
            $result | Should -BeOfType [long]
        }
    }

    Context "invalid operands throw a terminating error naming the accessor" {

        It "throws for `$null" {
            { ConvertTo-ConditionNumber -Value $null -Accessor 'add' } | Should -Throw '*add*'
        }

        It "throws for a boolean operand" {
            { ConvertTo-ConditionNumber -Value $true -Accessor 'mul' } | Should -Throw '*boolean*'
        }

        It "throws for a non-numeric string" {
            { ConvertTo-ConditionNumber -Value 'not-a-number' -Accessor 'div' } | Should -Throw '*not numeric*'
        }

        It "includes the accessor name in the error message" {
            { ConvertTo-ConditionNumber -Value 'nope' -Accessor 'mod' } | Should -Throw '*mod*'
        }
    }
}
