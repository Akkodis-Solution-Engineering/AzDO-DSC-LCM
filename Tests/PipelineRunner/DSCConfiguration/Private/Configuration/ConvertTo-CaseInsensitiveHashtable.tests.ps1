
Describe "ConvertTo-CaseInsensitiveHashtable Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'ConvertTo-CaseInsensitiveHashtable.ps1').FullName
        . $preParseFilePath

    }

    Context "With a scalar value" {

        It "Returns a string unchanged" {
            ConvertTo-CaseInsensitiveHashtable -InputObject 'value' | Should -Be 'value'
        }

        It "Returns an integer unchanged" {
            ConvertTo-CaseInsensitiveHashtable -InputObject 42 | Should -Be 42
        }

        It "Returns $null unchanged" {
            ConvertTo-CaseInsensitiveHashtable -InputObject $null | Should -BeNullOrEmpty
        }
    }

    Context "With a case-sensitive dictionary" {

        It "Rebuilds it as a case-insensitive [hashtable]" {
            $ordered = [System.Management.Automation.OrderedHashtable]::new()
            $ordered['type'] = 'File'

            $result = ConvertTo-CaseInsensitiveHashtable -InputObject $ordered

            $result | Should -BeOfType ([System.Collections.Hashtable])
        }

        It "Preserves values under case-insensitive lookup" {
            $ordered = [System.Management.Automation.OrderedHashtable]::new()
            $ordered['Type'] = 'File'

            $result = ConvertTo-CaseInsensitiveHashtable -InputObject $ordered

            $result['type'] | Should -Be 'File'
            $result['TYPE'] | Should -Be 'File'
        }

        It "Recurses into nested dictionaries" {
            $ordered = [System.Management.Automation.OrderedHashtable]::new()
            $nested = [System.Management.Automation.OrderedHashtable]::new()
            $nested['Condition'] = 'true'
            $ordered['Properties'] = $nested

            $result = ConvertTo-CaseInsensitiveHashtable -InputObject $ordered

            $result.Properties | Should -BeOfType ([System.Collections.Hashtable])
            $result.Properties['condition'] | Should -Be 'true'
        }
    }

    Context "With an enumerable value" {

        It "Rebuilds an array element by element, preserving order" {
            $items = @(
                [System.Management.Automation.OrderedHashtable]::new()
                [System.Management.Automation.OrderedHashtable]::new()
            )
            $items[0]['Name'] = 'First'
            $items[1]['Name'] = 'Second'

            $result = ConvertTo-CaseInsensitiveHashtable -InputObject $items

            $result.Count | Should -Be 2
            $result[0]['name'] | Should -Be 'First'
            $result[1]['name'] | Should -Be 'Second'
        }

        It "Wraps a single-element collection so it is still returned as an array" {
            $items = @('OnlyOne')

            $result = @(ConvertTo-CaseInsensitiveHashtable -InputObject $items)

            $result.Count | Should -Be 1
            $result[0] | Should -Be 'OnlyOne'
        }

        It "Treats a string as a scalar leaf, not an enumerable" {
            $result = ConvertTo-CaseInsensitiveHashtable -InputObject 'a string value'

            $result | Should -Be 'a string value'
            $result | Should -BeOfType ([string])
        }
    }
}
