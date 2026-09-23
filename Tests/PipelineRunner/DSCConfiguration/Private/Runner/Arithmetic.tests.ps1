
Describe "Arithmetic Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {

        # Load the helper functions these accessors depend on, plus the accessors themselves.
        $functionFiles = Get-FunctionPath @(
            'ConvertTo-ConditionNumber.ps1',
            'Expand-ConditionArgumentList.ps1',
            'add.ps1',
            'sub.ps1',
            'mul.ps1',
            'div.ps1',
            'mod.ps1',
            'min.ps1',
            'max.ps1',
            'int.ps1',
            'float.ps1',
            'coalesce.ps1'
        )

        foreach ($functionFile in $functionFiles) {
            . $functionFile.FullName
        }

    }

    Context "add" {

        It "should add two whole numbers" {
            add -Left 1 -Right 2 | Should -Be 3
        }

        It "should coerce string operands to numbers" {
            add -Left '7' -Right 3 | Should -Be 10
        }

        It "should return a whole number when both operands are whole" {
            (add -Left 1 -Right 2) | Should -BeOfType [long]
        }

        It "should add a fractional operand as a real number" {
            add -Left 2.5 -Right 3 | Should -Be 5.5
        }

        It "should throw when an operand is `$null" {
            { add -Left $null -Right 1 } | Should -Throw
        }

        It "should throw when an operand is not numeric" {
            { add -Left 'not-a-number' -Right 1 } | Should -Throw
        }
    }

    Context "sub" {

        It "should subtract the right operand from the left" {
            sub -Left 10 -Right 3 | Should -Be 7
        }

        It "should respect operand order" {
            sub -Left 3 -Right 10 | Should -Be -7
        }

        It "should coerce string operands to numbers" {
            sub -Left '10' -Right '4' | Should -Be 6
        }

        It "should throw when an operand is not numeric" {
            { sub -Left 'nope' -Right 1 } | Should -Throw
        }
    }

    Context "mul" {

        It "should multiply two whole numbers" {
            mul -Left 3 -Right 4 | Should -Be 12
        }

        It "should multiply a fractional operand as a real number" {
            mul -Left 2.5 -Right 2 | Should -Be 5.0
        }

        It "should coerce string operands to numbers" {
            mul -Left '3' -Right '4' | Should -Be 12
        }

        It "should throw when an operand is not numeric" {
            { mul -Left 'nope' -Right 1 } | Should -Throw
        }
    }

    Context "div" {

        It "should truncate toward zero when both operands are whole" {
            div -Left 7 -Right 2 | Should -Be 3
        }

        It "should perform real division when either operand is fractional" {
            div -Left 7.5 -Right 2 | Should -Be 3.75
        }

        It "should perform real division when the left operand is fractional" {
            div -Left 7.0 -Right 2 | Should -Be 3.5
        }

        It "should throw on division by zero" {
            { div -Left 5 -Right 0 } | Should -Throw
        }

        It "should throw when an operand is not numeric" {
            { div -Left 'nope' -Right 1 } | Should -Throw
        }
    }

    Context "mod" {

        It "should return the remainder of division" {
            mod -Left 7 -Right 3 | Should -Be 1
        }

        It "should take the sign of the dividend" {
            mod -Left -7 -Right 3 | Should -Be -1
        }

        It "should throw on division by zero" {
            { mod -Left 5 -Right 0 } | Should -Throw
        }

        It "should throw when an operand is not numeric" {
            { mod -Left 'nope' -Right 1 } | Should -Throw
        }
    }

    Context "min" {

        It "should return the smallest of the operands written out" {
            min 3 1 2 | Should -Be 1
        }

        It "should return the smallest of a single array operand" {
            min @(9, 4, 7) | Should -Be 4
        }

        It "should compare string operands numerically, not lexically" {
            min '9' '10' | Should -Be 9
        }

        It "should throw when called with no operands" {
            { min } | Should -Throw
        }
    }

    Context "max" {

        It "should return the largest of the operands written out" {
            max 3 1 2 | Should -Be 3
        }

        It "should return the largest of a single array operand" {
            max @(9, 4, 7) | Should -Be 9
        }

        It "should compare string operands numerically, not lexically" {
            max '9' '10' | Should -Be 10
        }

        It "should throw when called with no operands" {
            { max } | Should -Throw
        }
    }

    Context "int" {

        It "should convert a numeric string to a whole number" {
            int '8080' | Should -Be 8080
        }

        It "should truncate a positive fractional value toward zero" {
            int 2.9 | Should -Be 2
        }

        It "should truncate a negative fractional value toward zero" {
            int -2.9 | Should -Be -2
        }

        It "should return a [long]" {
            (int '7') | Should -BeOfType [long]
        }

        It "should throw when the value is not numeric" {
            { int 'nope' } | Should -Throw
        }
    }

    Context "float" {

        It "should convert a whole number to a real number" {
            float 7 | Should -Be 7.0
        }

        It "should return a [double]" {
            (float 7) | Should -BeOfType [double]
        }

        It "should convert a numeric string to a real number" {
            float '3.5' | Should -Be 3.5
        }

        It "should keep a division real when combined with div" {
            . (Get-FunctionPath 'div.ps1').FullName
            div (float 7) 2 | Should -Be 3.5
        }

        It "should throw when the value is not numeric" {
            { float 'nope' } | Should -Throw
        }
    }

    Context "coalesce" {

        It "should return the first non-null operand" {
            coalesce $null 'fallback' | Should -Be 'fallback'
        }

        It "should return `$null when every operand is `$null" {
            coalesce $null $null | Should -Be $null
        }

        It "should treat an empty string as a value, not as absent" {
            coalesce '' 'fallback' | Should -Be ''
        }

        It "should return the most specific (first) non-null operand" {
            coalesce 'specific' 'fallback' | Should -Be 'specific'
        }

        It "should accept a single array operand" {
            coalesce @($null, 'second') | Should -Be 'second'
        }
    }
}
