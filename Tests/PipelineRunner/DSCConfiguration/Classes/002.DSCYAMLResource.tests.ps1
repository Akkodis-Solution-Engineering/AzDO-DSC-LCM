
Describe "DSC_Resource Class Tests" -Tag Unit {

    BeforeAll {

        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource = (Get-FunctionPath '002.DSC_Resource.ps1').FullName

        . $DSCBaseResource
        . $DSC_Resource
        
    }

    Context "Constructor Tests" {

        It "Should throw error if name is missing" {
            $ht = @{
                type       = 'Module\Type'
                properties = @(@{})
            }
            { [DSC_Resource]::new($ht) } | Should -Throw "*Name is mandatory*"
        }

        It "Should throw error if properties are missing or invalid" {
            $ht = @{
                name = "TestResource"
                type = 'Module\Type'
            }
            { [DSC_Resource]::new($ht) } | Should -Throw "*Properties is mandatory*"
        }

        It "Should initialize all properties correctly when valid hashtable is provided" {

            $ht = @{
                name               = "TestResource"
                type               = 'Module\Type'
                properties         = @{ key = "value" }
                condition          = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn          = "SomeDependency"
                mergable           = $true
            }

            $resource = [DSC_Resource]::new($ht)

            $resource.name  | Should -Be "TestResource"
            $resource.type  | Should -Be 'Module\Type'
            $resource.properties    | Should -Be $ht['properties']
            $resource.condition     | Should -Be "SomeCondition"
            $resource.postExecutionScript | Should -Be "SomeScript"
            $resource.dependsOn     | Should -Be "SomeDependency"
            $resource.mergable      | Should -Be $true

        }

    }
    
}
