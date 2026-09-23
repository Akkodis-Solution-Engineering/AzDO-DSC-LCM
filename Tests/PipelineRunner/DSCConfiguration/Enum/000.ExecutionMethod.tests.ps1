
Describe "ExecutionMethod Enum Tests" -Tag Unit {

    BeforeAll {

        $ExecutionMethod = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName

        . $ExecutionMethod

    }

    It "Defines exactly the values None, Test and Set" {
        [enum]::GetNames([ExecutionMethod]) | Should -Be @('None', 'Test', 'Set')
    }

    It "Can be cast from the string 'None'" {
        [ExecutionMethod]'None' | Should -Be ([ExecutionMethod]::None)
    }

    It "Can be cast from the string 'Test'" {
        [ExecutionMethod]'Test' | Should -Be ([ExecutionMethod]::Test)
    }

    It "Can be cast from the string 'Set'" {
        [ExecutionMethod]'Set' | Should -Be ([ExecutionMethod]::Set)
    }

    It "Throws when cast from a value that is not a defined member" {
        { [ExecutionMethod]'Invalid' } | Should -Throw
    }

    It "Defaults an uninitialized [ExecutionMethod] variable to None (the first-declared member)" {
        $method = [ExecutionMethod]0
        $method | Should -Be ([ExecutionMethod]::None)
    }

    It "Orders the underlying values as None, Test, Set" {
        [int][ExecutionMethod]::None | Should -Be 0
        [int][ExecutionMethod]::Test | Should -Be 1
        [int][ExecutionMethod]::Set  | Should -Be 2
    }

}
