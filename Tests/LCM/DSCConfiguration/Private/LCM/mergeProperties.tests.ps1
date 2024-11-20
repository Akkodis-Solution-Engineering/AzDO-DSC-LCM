
Describe "Join-Properties Function Tests" {

    BeforeAll {
        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'mergeProperties.ps1').FullName
        $orderHashTable = (Get-FunctionPath 'sortDictionary.ps1').FullName

        . $preParseFilePath
        . $orderHashTable
        
    }

    It "Returns null when both inputs are null" {
        $result = Join-Properties -source $null -merge $null
        $result | Should -Be $null
    }

    It "Returns merge hashtable when source is null" {
        $merge = @{ Key1 = 'Value1' }
        $result = Join-Properties -source $null -merge $merge
        $result | Should -BeExactly $merge
    }

    It "Returns source hashtable when merge is null" {
        $source = @{ Key1 = 'Value1' }
        $result = Join-Properties -source $source -merge $null
        $result | Should -BeExactly $source
    }

    It "Merges two hashtables with unique keys" {
        $source = @{ Key1 = 'Value1' }
        $merge = @{ Key2 = 'Value2' }
        $expected = @{ Key1 = 'Value1'; Key2 = 'Value2' }
        $result = Join-Properties -source $source -merge $merge
        $result.Key1 | Should -Be $expected.Key1
        $result.Key2 | Should -Be $expected.Key2
    }

    It "Prefers source value on type mismatch" {
        
        Mock Write-Warning

        $source = @{ Key1 = 123 }
        $merge = @{ Key1 = 'StringValue' }
        $expected = @{ Key1 = 123 }
        $result = Join-Properties -source $source -merge $merge
        $result.Key1 | Should -Be $expected.Key1
    }

    It "Recursively merges nested hashtables" {
        $source = @{ Nested = @{ Key1 = 'Value1' } }
        $merge = @{ Nested = @{ Key2 = 'Value2' } }
        $expected = @{ Nested = @{ Key1 = 'Value1'; Key2 = 'Value2' } }
        $result = Join-Properties -source $source -merge $merge
        $result.Nested.Key1 | Should -Be $expected.Nested.Key1
        $result.Nested.Key2 | Should -Be $expected.Nested.Key2
    }

    It "Combines collections without duplicates" {
        $source = @{ List = @(1, 2, 3) }
        $merge = @{ List = @(3, 4, 5) }
        $expected = @{ List = @(1, 2, 3, 4, 5) }
        $result = Join-Properties -source $source -merge $merge
        $result['List'] | Should -BeExactly $expected['List']
    }

    It "Combines string arrays uniquely" {
        $source = @{ Strings = @('a', 'b') }
        $merge = @{ Strings = @('b', 'c') }
        $expected = @{ Strings = @('a', 'b', 'c') }
        $result = Join-Properties -source $source -merge $merge
        @($result['Strings']) | Should -BeExactly @($expected['Strings'])
    }

    It "Combines string arrays and hashes uniquely" {
        $source = @{ Strings = @('a', 'b'); Hash = @{ Key = 'Value' } }
        $merge = @{ Strings = @('b', 'c'); Hash = @{ Key2 = 'Value2' } }
        $expected = @{ Strings = @('a', 'b', 'c'); Hash = @{ Key = 'Value'; Key2 = 'Value2' } }

        $result = Join-Properties -source $source -merge $merge
        @($result['Strings']) | Should -BeExactly @($expected['Strings'])
        $result['Hash'].Key | Should -BeExactly $expected['Hash'].Key
        $result['Hash'].Key2 | Should -BeExactly $expected['Hash'].Key2
    }

    It "Combines complex collections uniquely" {
        $source = @{ List = @(1, 2, 3); Hash = @{ Key = 'Value' } }
        $merge = @{ List = @(3, 4, 5); Hash = @{ Key2 = 'Value2' } }
        $expected = @{ List = @(1, 2, 3, 4, 5); Hash = @{ Key = 'Value'; Key2 = 'Value2' } }

        $result = Join-Properties -source $source -merge $merge
        $result['List'] | Should -BeExactly $expected['List']
        $result['Hash'].Key | Should -BeExactly $expected['Hash'].Key
        $result['Hash'].Key2 | Should -BeExactly $expected['Hash'].Key2
    }

    It "Combines complex nested collections uniquely" {
        $source = @{ List = @(1, 2, 3); Hash = @{ Key = 'Value'; Nested = @{ Key = 'Value' } } }
        $merge = @{ List = @(3, 4, 5); Hash = @{ Key2 = 'Value2'; Nested = @{ Key2 = 'Value2' } } }
        $expected = @{ List = @(1, 2, 3, 4, 5); Hash = @{ Key = 'Value'; Key2 = 'Value2'; Nested = @{ Key = 'Value'; Key2 = 'Value2' } } }

        $result = Join-Properties -source $source -merge $merge
        $result['List'] | Should -BeExactly $expected['List']
        $result['Hash'].Key | Should -BeExactly $expected['Hash'].Key
        $result['Hash'].Key2 | Should -BeExactly $expected['Hash'].Key2
        $result['Hash'].Nested.Key | Should -BeExactly $expected['Hash'].Nested.Key
        $result['Hash'].Nested.Key2 | Should -BeExactly $expected['Hash'].Nested.Key2
    }

}
