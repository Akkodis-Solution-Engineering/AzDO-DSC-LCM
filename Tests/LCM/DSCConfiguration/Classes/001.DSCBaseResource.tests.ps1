
Describe "DSCBaseResource Class Tests" -Tag Unit {

    BeforeAll {
        # Mocking the DSCBaseResource class
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        . $DSCBaseResource

        # Mocking the DSCResourceType enumeration or class if it's not defined elsewhere
        Enum DSCResourceType {
            TypeA
            TypeB
        }

    }


    Context "Property Initialization Tests" {
        It "Should initialize name property correctly" {
            $resource = [DSCBaseResource]::new()
            $resource.name = "MyResource"
            $resource.name | Should -Be "MyResource"
        }

        It "Should initialize type property correctly" {
            $resource = [DSCBaseResource]::new()
            $resource.type = [DSCResourceType]::TypeA
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
            $resource.type = [DSCResourceType]::TypeA

            $fullResourceName = $resource.getFullResourceName()
            $fullResourceName | Should -Be "TypeA\MyResource"
        }

        It "Should handle null name gracefully" {
            $resource = [DSCBaseResource]::new()
            $resource.type = [DSCResourceType]::TypeB

            { $resource.getFullResourceName() } | Should -Throw
        }

    }
}
