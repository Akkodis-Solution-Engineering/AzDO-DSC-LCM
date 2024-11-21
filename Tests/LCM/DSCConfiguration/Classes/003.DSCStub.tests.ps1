# Import necessary modules or scripts if needed
# . $PSScriptRoot\YourScriptWithDSCStubClass.ps1

Describe "DSCStub Class Tests" -Tag Unit {

    BeforeAll {

        # Mocking the DSCBaseResource class
        $enumsResource = (Get-FunctionPath 'DSCResourceType.ps1').FullName
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCResource = (Get-FunctionPath '002.DSCYAMLResource.ps1').FullName
        $DSCStubResource = (Get-FunctionPath '003.DSCStub.ps1').FullName

        $mergePropertiesPath = (Get-FunctionPath 'mergeProperties.ps1').FullName

        . $enumsResource
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
            }

            $stub = [DSCStub]::new($ht)

            $stub.name | Should -Be "StubResource"
            $stub.type | Should -Be 'Stub'
            $stub.properties | Should -Be $ht['properties']
            $stub.merge_with | Should -Be "TargetResource"
        }
    }

    Context "Merge Method Tests" {
        It "Should throw error if merge_with resource not found" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "NonExistentResource"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSCYAMLResource]::new(@{
                    name       = "SomeResource"
                    type       = [DSCResourceType]::Resource
                    properties = @{ key = "value" }
                })
                [DSCYAMLResource]::new(@{
                    name       = "SomeResource2"
                    type       = [DSCResourceType]::Resource
                    properties = @{ key = "value" }
                })                
            )

            { $stub.merge($dscResources) } | Should -Throw "*Resource 'NonExistentResource' not found in provided DSC resources*"
        }

        It "Should throw error if merge_with resource is found multiple times" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "Resource\DuplicateResource"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSCYAMLResource]::new(@{
                    name       = "DuplicateResource"
                    type       = [DSCResourceType]::Resource
                    properties = @{ key = "value" }
                })
                [DSCYAMLResource]::new(@{
                    name       = "DuplicateResource"
                    type       = [DSCResourceType]::Resource
                    properties = @{ key = "value" }
                })                
            )

            { $stub.merge($dscResources) } | Should -Throw "*was found multiple times (count*"
        }

        It "Should throw error if merge_with resource is not mergable" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "value" }
                merge_with = "Resource\NonMergeableResource"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSCYAMLResource]::new(@{
                    name       = "NonMergeableResource"
                    type       = [DSCResourceType]::Resource
                    properties = @{ key = "value" }
                })
            )

            { $stub.merge($dscResources) } | Should -Throw "*does not contain a 'mergable' property*"
        }

        It "Should merge properties correctly when conditions are met" {
            $ht = @{
                name       = "StubResource"
                properties = @{ key = "newValue" }
                merge_with = "Resource\MergeableResource"
            }
            $stub = [DSCStub]::new($ht)

            $dscResources = @(
                [DSCYAMLResource]::new(@{
                    name       = "MergeableResource"
                    type       = [DSCResourceType]::Resource
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
