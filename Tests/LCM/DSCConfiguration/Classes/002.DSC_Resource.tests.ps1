
Describe "DSC_Resource Class Tests" -Tag Unit {

    BeforeAll {

        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $ExecutionMethod = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName

        # Load the Enums First
        . $ExecutionMethod
        # Load the Classes
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

        It "Should initialize all properties correctly when valid hashtable is provided - Standard Case" {

            $ht = @{
                name                = "TestResource"
                type                = 'Module\Type'
                properties          = @{ key = "value" }
                condition           = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn           = "SomeDependency"
                mergable            = $true
            }

            $resource = [DSC_Resource]::new($ht)

            $resource.name  | Should -Be "TestResource"
            $resource.type  | Should -Be 'Module\Type'
            $resource.properties    | Should -Be $ht['properties']
            $resource.condition     | Should -Be "SomeCondition"
            $resource.postExecutionScript | Should -Be "SomeScript"
            $resource.dependsOn     | Should -Be "SomeDependency"
            $resource.mergable      | Should -Be $true
            $resource.executionMethodOverride | Should -Be 'None'

        }

        It "Should initialize all properties correctly when valid hashtable is provided - Custom Execution Method" {

            $ht = @{
                name                = "TestResource"
                type                = 'Module\Type'
                properties          = @{ key = "value" }
                condition           = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn           = "SomeDependency"
                mergable            = $true
                executionMethodOverride = 'Set'
            }

            $resource = [DSC_Resource]::new($ht)

            $resource.name  | Should -Be "TestResource"
            $resource.type  | Should -Be 'Module\Type'
            $resource.properties    | Should -Be $ht['properties']
            $resource.condition     | Should -Be "SomeCondition"
            $resource.postExecutionScript | Should -Be "SomeScript"
            $resource.dependsOn     | Should -Be "SomeDependency"
            $resource.mergable      | Should -Be $true
            $resource.executionMethodOverride | Should -Be 'Set'

        }

        It "Should initialize all properties correctly when valid hashtable is provided - Test Execution Method" {

            $ht = @{
                name                = "TestResource"
                type                = 'Module\Type'
                properties          = @{ key = "value" }
                condition           = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn           = "SomeDependency"
                mergable            = $true
                executionMethodOverride = 'Test'
            }

            $resource = [DSC_Resource]::new($ht)

            $resource.name  | Should -Be "TestResource"
            $resource.type  | Should -Be 'Module\Type'
            $resource.properties    | Should -Be $ht['properties']
            $resource.condition     | Should -Be "SomeCondition"
            $resource.postExecutionScript | Should -Be "SomeScript"
            $resource.dependsOn     | Should -Be "SomeDependency"
            $resource.mergable      | Should -Be $true
            $resource.executionMethodOverride | Should -Be 'Test'

        }

        It "Should throw error if executionMethodOverride is not valid" {
            $ht = @{
                name                = "TestResource"
                type                = 'Module\Type'
                properties          = @{ key = "value" }
                condition           = "SomeCondition"
                postExecutionScript = "SomeScript"
                dependsOn           = "SomeDependency"
                mergable            = $true
                executionMethodOverride = 'InvalidMethod'
            }
            { [DSC_Resource]::new($ht) } | Should -Throw "*Invalid executionMethodOverride value*"
        }

    }
    
}
