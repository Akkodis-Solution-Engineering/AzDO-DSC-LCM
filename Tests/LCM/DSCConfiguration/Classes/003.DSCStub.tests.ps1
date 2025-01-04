# Import necessary modules or scripts if needed
# . $PSScriptRoot\YourScriptWithDSCStubClass.ps1

Describe "DSCStub Class Tests" -Tag Unit {

    BeforeAll {

        # Mocking the DSCBaseResource class
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCResource = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $DSCStubResource = (Get-FunctionPath '003.DSCStub.ps1').FullName

        $mergePropertiesPath = (Get-FunctionPath 'mergeProperties.ps1').FullName

        . $DSCBaseResource
        . $DSCResource
        . $DSCStubResource
        
        . $mergePropertiesPath

    }

    Context "Constructor Tests" {
        It "Should throw error if any mandatory property is missing" {
            $ht = @{
                name       = "StubResource"
                properties = @{}
                # merge_with is missing
            }
            { [DSCStub]::new($ht) } | Should -Throw "*All properties (name, type, properties, merge_with) must be provided*"
        }

        It "Should initialize all properties correctly when valid hashtable is provided" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "TargetResource"
                type       = "MockType"
            }

            $stub = [DSCStub]::new($ht)

            $stub.name | Should -Be "StubResource"
            $stub.type | Should -Be 'MockType'
            $stub.properties | Should -Be $ht['properties']
            $stub.merge_with | Should -Be "TargetResource"
        }
    }

    Context "Merge Method Tests" {

        It "Should merge even when the merge_with seperator is a backslash instead of a forwardslash" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "MockType\TargetResource"
                type = "MockType"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSC_Resource]::new(@{
                    name       = "TargetResource"
                    type       = 'MockType'
                    properties = @{ key = "value" }
                    mergable   = $true
                })                
            )

            Mock Join-Properties { 
                param (
                    [HashTable]$source, 
                    [HashTable]$merge
                )
                return $merge
            }

            $mergedResources = $stub.merge($dscResources)

            $mergedResources[0].properties.key | Should -Be "value"
        }

        It "Should throw error if merge_with resource not found" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                type        = "MockType"
                merge_with = "NonExistentResource"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSC_Resource]::new(@{
                    name       = "SomeResource"
                    type       = 'MockType'
                    properties = @{ key = "value" }
                })
                [DSC_Resource]::new(@{
                    name       = "SomeResource2"
                    type       = 'MockType'                    
                    properties = @{ key = "value" }
                })                
            )

            { $stub.merge($dscResources) } | Should -Throw "*Resource 'NonExistentResource' not found in provided DSC resources*"
        }

        It "Should throw error if merge_with resource is found multiple times" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "MockType/DuplicateResource"
                type = "MockType"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSC_Resource]::new(@{
                    name       = "DuplicateResource"
                    type       = 'MockType'
                    properties = @{ key = "value" }
                })
                [DSC_Resource]::new(@{
                    name       = "DuplicateResource"
                    type       = 'MockType'
                    properties = @{ key = "value" }
                })                
            )

            { $stub.merge($dscResources) } | Should -Throw "*was found multiple times (count*"
        }

        It "Should throw error if merge_with resource is not mergable" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "Type/NonMergeableResource"
                type = "MockType"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSC_Resource]::new(@{
                    name       = "NonMergeableResource"
                    type       = 'Type'
                    properties = @{ key = "value" }
                })
            )

            { $stub.merge($dscResources) } | Should -Throw "*does not contain a 'mergable' property*"
        }

        It "Should merge properties correctly when conditions are met" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "newValue" }
                merge_with = "MockType/MergeableResource"
                type = "MockType"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSC_Resource]::new(@{
                    name       = "MergeableResource"
                    type       = 'MockType'
                    properties = @{ key = "value" }
                    mergable   = $true
                })                
            )

            Mock Join-Properties { 
                param (
                    [HashTable]$source, 
                    [HashTable]$merge
                )
                return $merge
            }

            $mergedResources = $stub.merge($dscResources)

            $mergedResources[0].properties.key | Should -Be "newValue"
        }

    }
}
