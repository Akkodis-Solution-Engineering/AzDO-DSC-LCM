
Describe "Expand-ConditionArgumentList Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'Expand-ConditionArgumentList.ps1').FullName
    }

    It "returns an empty array for `$null" {
        , (Expand-ConditionArgumentList -Value $null) | Should -Be @()
    }

    It "returns an empty array for an empty collection" {
        , (Expand-ConditionArgumentList -Value @()) | Should -Be @()
    }

    It "passes through a flat list of scalar operands unchanged" {
        $result = Expand-ConditionArgumentList -Value @('a', 'b', 'c')
        $result | Should -Be @('a', 'b', 'c')
    }

    It "flattens a single nested array operand" {
        $result = Expand-ConditionArgumentList -Value @(, @('a', 'b', 'c'))
        $result | Should -Be @('a', 'b', 'c')
    }

    It "flattens a mix of nested arrays and scalars" {
        $result = Expand-ConditionArgumentList -Value @(@(1, 2), 3)
        $result | Should -Be @(1, 2, 3)
    }

    It "flattens recursively through multiple levels of nesting" {
        $result = Expand-ConditionArgumentList -Value @(@(@(1, 2), 3), 4)
        $result | Should -Be @(1, 2, 3, 4)
    }

    It "treats a string operand as a single scalar rather than enumerating its characters" {
        $result = Expand-ConditionArgumentList -Value @('abc')
        $result | Should -Be @('abc')
        $result.Count | Should -Be 1
    }

    It "treats a hashtable operand as a single value rather than expanding its entries" {
        # Forced back into an array with the unary comma: Expand-ConditionArgumentList returns
        # its array via `return`, which PowerShell unwraps to a bare scalar when the array has
        # exactly one element, same as any other function output.
        $hashtable = @{ Key = 'Value' }
        $result = @(Expand-ConditionArgumentList -Value @($hashtable))
        $result.Count | Should -Be 1
        $result[0] | Should -Be $hashtable
    }

    It "preserves `$null entries rather than dropping them" {
        $result = Expand-ConditionArgumentList -Value @('a', $null, 'b')
        $result.Count | Should -Be 3
        $result[1] | Should -BeNullOrEmpty
    }

    It "preserves a `$null entry nested inside an array" {
        $result = Expand-ConditionArgumentList -Value @(@('a', $null), 'b')
        $result.Count | Should -Be 3
        $result[1] | Should -BeNullOrEmpty
    }
}
