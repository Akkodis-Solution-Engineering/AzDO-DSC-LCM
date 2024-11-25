
Describe "sortDictionary Function Tests" -Tag Unit, LCM, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'sortDictionary.ps1').FullName

        . $preParseFilePath

    }

    It "Should return an empty hashtable when input is an empty hashtable" {
        $input = @{}
        $expected = @{}

        $result = sortDictionary -HashTable $input

        $result.keys | Should -BeNullOrEmpty
    }

    It "Should order a simple hashtable by keys" {
        $input = @{
            'z' = 1
            'a' = 2
            'm' = 3
        }
        $expected = [ordered]@{
            'a' = 2
            'm' = 3
            'z' = 1
        }

        $result = sortDictionary -HashTable $input

        @($result.Keys) | Should -Be @($expected.Keys)
    }

    It "Should order nested hashtables by keys" {
        $input = @{
            'outer' = @{
                'b' = 1
                'a' = 2
            }
        }
        $expected = @{
            'outer' = @{
                'a' = 2
                'b' = 1
            }
        }

        $result = sortDictionary -HashTable $input

        @($result['outer'].Keys) | Should -Be @($expected['outer'].Keys)
    }

    It "Should handle arrays of hashtables" {
        $input = @{
            'array' = @(
                @{ 'c' = 3; 'a' = 1 }
                @{ 'b' = 2; 'd' = 4 }
            )
        }
        $expected = @{
            'array' = @(
                @{ 'a' = 1; 'c' = 3 }
                @{ 'b' = 2; 'd' = 4 }
            )
        }

        $result = sortDictionary -HashTable $input

        @($result['array'][0].Keys) | Should -Be @($expected['array'][0].Keys)
        @($result['array'][1].Keys) | Should -Be @($expected['array'][1].Keys)
    }

    It "Should return the same hashtable when keys are already ordered" {
        $ht = @{
            'a' = 1
            'b' = 2
            'c' = 3
        }
        $expected = @{
            'a' = 1
            'b' = 2
            'c' = 3
        }

        $result = sortDictionary -HashTable $ht

        @($result.Keys) | Should -Be @($expected.Keys)
        $result.a | Should -Be $expected.a
        $result.b | Should -Be $expected.b
        $result.c | Should -Be $expected.c
        
    }
}
