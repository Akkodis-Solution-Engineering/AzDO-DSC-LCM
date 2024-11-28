
Describe "DSCBaseResource Class Tests" -Tag Unit {

    BeforeAll {
        # Mocking the DSCBaseResource class
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        . $DSCBaseResource

    }


    Context "Property Initialization Tests" {
        It "Should initialize name property correctly" {
            $resource = [DSCBaseResource]::new()
            $resource.name = "MyResource"
            $resource.name | Should -Be "MyResource"
        }

        It "Should initialize type property correctly" {
            $resource = [DSCBaseResource]::new()
            $resource.type = 'TypeA'
            $resource.type | Should -Be 'TypeA'

        }

        It "Should initialize properties as an empty array" {
            $resource = [DSCBaseResource]::new()
            $resource.properties | Should -BeNullOrEmpty
        }
    }

    Context "Method Tests" {
        It "Should return correct full resource name" {
            $resource = [DSCBaseResource]::new()
            $resource.name = "MyResource"
            $resource.type = 'TypeA'

            $fullResourceName = $resource.getFullResourceName()
            $fullResourceName | Should -Be "TypeA/MyResource"
        }

        It "Should handle null name gracefully" {
            $resource = [DSCBaseResource]::new()
            $resource.type = 'TypeB'

            { $resource.getFullResourceName() } | Should -Throw
        }

    }
}
