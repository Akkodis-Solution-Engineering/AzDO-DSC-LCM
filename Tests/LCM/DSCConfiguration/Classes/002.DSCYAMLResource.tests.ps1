
Describe "DSCYAMLResource Class Tests" -Tag Unit {

    BeforeAll {

        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCYAMLResource = (Get-FunctionPath '002.DSCYAMLResource.ps1').FullName

        . $DSCBaseResource
        . $DSCYAMLResource
        
        # Mocking the DSCResourceType enumeration or class if it's not defined elsewhere
        Enum DSCResourceType {
            Resource
        }

    }

    Context "Constructor Tests" {

        It "Should throw error if name is missing" {
            $ht = @{
                type       = [DSCResourceType]::Resource
                properties = @(@{})
            }
            { [DSCYAMLResource]::new($ht) } | Should -Throw "*Name is mandatory*"
        }

        It "Should throw error if properties are missing or invalid" {
            $ht = @{
                name = "TestResource"
                type = [DSCResourceType]::Resource
            }
            { [DSCYAMLResource]::new($ht) } | Should -Throw "*Properties is mandatory*"
        }

        It "Should initialize all properties correctly when valid hashtable is provided" {

            $ht = @{
                name               = "TestResource"
                properties         = @{ key = "value" }
                condition          = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn          = "SomeDependency"
                mergable           = $true
            }

            $resource = [DSCYAMLResource]::new($ht)

            $resource.name  | Should -Be "TestResource"
            $resource.properties    | Should -Be $ht['properties']
            $resource.condition     | Should -Be "SomeCondition"
            $resource.postExecutionScript | Should -Be "SomeScript"
            $resource.dependsOn     | Should -Be "SomeDependency"
            $resource.mergable      | Should -Be $true
            $resource.type  | Should -Be 'Resource'

        }

    }
    
}
