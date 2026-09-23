
Describe "String Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {

        $functionFiles = Get-FunctionPath @(
            'Expand-ConditionArgumentList.ps1',
            'concat.ps1',
            'contains.ps1',
            'startsWith.ps1',
            'toLower.ps1',
            'toUpper.ps1',
            'empty.ps1'
        )

        foreach ($functionFile in $functionFiles) {
            . $functionFile.FullName
        }

    }

    Context "concat" {

        It "should join operands written out with no separator" {
            concat 'a' 'b' | Should -Be 'ab'
        }

        It "should contribute an empty string for a `$null operand" {
            concat 'a' $null 'b' | Should -Be 'ab'
        }

        It "should return an empty string when called with no operands" {
            concat | Should -Be ''
        }

        It "should flatten a single array operand" {
            concat @('a', 'b', 'c') | Should -Be 'abc'
        }

        It "should convert numeric operands to their string form" {
            concat 'v' 1 '.' 2 | Should -Be 'v1.2'
        }
    }

    Context "contains" {

        It "should return `$true when a dictionary has the key, case-insensitively" {
            contains -Container @{ Boards = 1 } -Value 'boards' | Should -Be $true
        }

        It "should return `$false when a dictionary lacks the key" {
            contains -Container @{ Boards = 1 } -Value 'Repos' | Should -Be $false
        }

        It "should return `$true when an array contains an equal element" {
            contains -Container @('a', 'b', 'c') -Value 'B' | Should -Be $true
        }

        It "should return `$false when an array does not contain the element" {
            contains -Container @('a', 'b', 'c') -Value 'z' | Should -Be $false
        }

        It "should return `$true for a substring match, case-insensitively" {
            contains -Container 'Encrypt=True;Server=x' -Value 'encrypt=true' | Should -Be $true
        }

        It "should return `$false for a substring match when -CaseSensitive is set" {
            contains -Container 'Encrypt=True' -Value 'encrypt=true' -CaseSensitive | Should -Be $false
        }

        It "should return `$false for a `$null container" {
            contains -Container $null -Value 'x' | Should -Be $false
        }
    }

    Context "startsWith" {

        It "should return `$true when the value starts with the prefix, case-insensitively" {
            startsWith -Value 'Internal-Billing' -Prefix 'internal-' | Should -Be $true
        }

        It "should return `$false when the value does not start with the prefix" {
            startsWith -Value 'External-Billing' -Prefix 'internal-' | Should -Be $false
        }

        It "should return `$false for a case-mismatched prefix when -CaseSensitive is set" {
            startsWith -Value 'Internal-Billing' -Prefix 'internal-' -CaseSensitive | Should -Be $false
        }

        It "should treat a `$null value as an empty string" {
            startsWith -Value $null -Prefix '' | Should -Be $true
        }

        It "should return `$true for an empty prefix" {
            startsWith -Value 'anything' -Prefix '' | Should -Be $true
        }
    }

    Context "toLower" {

        It "should lower-case a string" {
            toLower 'Production' | Should -Be 'production'
        }

        It "should return an empty string for `$null" {
            toLower $null | Should -Be ''
        }

        It "should convert a non-string value to its string form first" {
            toLower 123 | Should -Be '123'
        }
    }

    Context "toUpper" {

        It "should upper-case a string" {
            toUpper 'weu' | Should -Be 'WEU'
        }

        It "should return an empty string for `$null" {
            toUpper $null | Should -Be ''
        }

        It "should convert a non-string value to its string form first" {
            toUpper 123 | Should -Be '123'
        }
    }

    Context "empty" {

        It "should return `$true for `$null" {
            empty $null | Should -Be $true
        }

        It "should return `$true for an empty string" {
            empty '' | Should -Be $true
        }

        It "should return `$false for a whitespace-only string" {
            empty ' ' | Should -Be $false
        }

        It "should return `$true for an empty array" {
            empty @() | Should -Be $true
        }

        It "should return `$false for a non-empty array" {
            empty @(1) | Should -Be $false
        }

        It "should return `$true for an empty hashtable" {
            empty @{} | Should -Be $true
        }

        It "should return `$false for a non-empty hashtable" {
            empty @{ Key = 'Value' } | Should -Be $false
        }

        It "should return `$false for `$false, since it asks presence, not truthiness" {
            empty $false | Should -Be $false
        }

        It "should return `$false for 0, since it asks presence, not truthiness" {
            empty 0 | Should -Be $false
        }
    }
}
