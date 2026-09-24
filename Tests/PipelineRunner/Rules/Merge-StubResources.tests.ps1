
Describe "Merge-StubResources" -Tag Unit, PipelineRunner, Rules, Sort {

    BeforeAll {

        $DSCConfigurationFile   = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        $DSCBaseResource        = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource           = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $DSCStub                = (Get-FunctionPath '003.DSCStub.ps1').FullName
        $DSCCompositeResource   = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName
        $ExecutionMethod        = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName

        # Load the functions to test
        $preParseFilePath       = (Get-FunctionPath 'Merge-StubResources.ps1').FullName
        $joinPropertiesFilePath = (Get-FunctionPath 'mergeProperties.ps1').FullName
        $sortHashtableFilePath  = (Get-FunctionPath 'sortDictionary.ps1').FullName

        . $ExecutionMethod

        . $DSCConfigurationFile
        . $DSCBaseResource
        . $DSC_Resource
        . $DSCStub
        . $DSCCompositeResource
        . $joinPropertiesFilePath
        . $sortHashtableFilePath

        # Define mock DSCStub and resource objects for testing
        $DSCStub = [DSCStub]::New(@{ 
            name = 'ResourceA'
            merge_with = 'ResourceType/ResourceName/TargetResource'
            type = 'DSCStub'
            properties = @{ Key1 = 'Value1' }
        })

        $TargetResource = @{ 
            Name = 'TargetResource';
            Type = 'ResourceType/ResourceName';
            Mergable = $true
            Properties = @{ Key2 = 'ExistingValue' }
        }

    }

    It "Returns original pipeline resources when no stub resources are present" {
        $pipelineResources = @($TargetResource)

        $result = . $preParseFilePath -PipelineResources $pipelineResources

        $result | Should -BeExactly $pipelineResources
    }

    It "Merges stub resources with target resources correctly" {
        $pipelineResources = @($DSCStub, $TargetResource)

        $result = . $preParseFilePath -PipelineResources $pipelineResources

        @($result).Count | Should -Be 1
        $result.properties['Key1'] | Should -Be 'Value1'
        $result.properties['Key2'] | Should -Be 'ExistingValue'
    }

    It "Throws when a stub resource's target is not found" {
        $pipelineResources = @($DSCStub)

        { . $preParseFilePath -PipelineResources $pipelineResources } | Should -Throw "*was not found*"
    }

    It "Throws when a stub resource's target is not found and there are other resources" {
        $missingStub = [DSCStub]::New(@{
            name = 'ResourceA'
            merge_with = 'ResourceType/ResourceName/NonExistentResource'
            type = 'DSCStub'
            properties = @{ Key1 = 'Value1' }
        })
        $pipelineResources = @($missingStub, $TargetResource)

        { . $preParseFilePath -PipelineResources $pipelineResources } | Should -Throw "*was not found*"
    }

    It "Throws when the target does not declare mergable: true" {
        $unmarkedTarget = @{
            Name = 'TargetResource'
            Type = 'ResourceType/ResourceName'
            Properties = @{ Key2 = 'ExistingValue' }
        }

        { . $preParseFilePath -PipelineResources @($DSCStub, $unmarkedTarget) } | Should -Throw "*mergable: true*"
    }

    It "Throws when the target identity matches more than one resource" {
        $pipelineResources = @($DSCStub, $TargetResource, $TargetResource.Clone())

        { . $preParseFilePath -PipelineResources $pipelineResources } | Should -Throw "*found 2 times*"
    }

    It "Overrides a target scalar with the stub value, later stubs winning" {
        $first = [DSCStub]::New(@{ name = 'First'; merge_with = 'ResourceType/ResourceName/Scalar'; type = 'DSCStub'; properties = @{ Visibility = 'public' } })
        $second = [DSCStub]::New(@{ name = 'Second'; merge_with = 'ResourceType/ResourceName/Scalar'; type = 'DSCStub'; properties = @{ Visibility = 'internal' } })
        $target = @{ Name = 'Scalar'; Type = 'ResourceType/ResourceName'; Mergable = $true; Properties = @{ Visibility = 'private'; Keep = 'Me' } }

        $result = . $preParseFilePath -PipelineResources @($first, $second, $target)

        $result.properties.Visibility | Should -Be 'internal'
        $result.properties.Keep | Should -Be 'Me'
    }

    It "Merges array-of-hashtable properties without losing entries" {
        $permissionStub = [DSCStub]::New(@{
            name = 'PermissionStub'
            merge_with = 'ResourceType/ResourceName/Permissions'
            type = 'DSCStub'
            properties = @{ Permissions = @(@{ Identity = 'B'; Permission = @{ Read = 'Allow' } }) }
        })
        $permissionTarget = @{
            Name = 'Permissions'
            Type = 'ResourceType/ResourceName'
            Mergable = $true
            Properties = @{ Permissions = [System.Collections.Generic.List[Object]]@(@{ Identity = 'A'; Permission = @{ Read = 'Allow' } }) }
        }

        $result = . $preParseFilePath -PipelineResources @($permissionStub, $permissionTarget)

        @($result.properties.Permissions).Identity | Should -Be @('B', 'A')
    }

    It "Merge multiple sub resources with the same target resource" {
        $DSCStub2 = [DSCStub]::New(@{ 
            name = 'ResourceB'
            merge_with = 'ResourceType/ResourceName/TargetResource'
            properties = @{ Key3 = 'Value3' }
            type = 'DSCStub'
        })
        $pipelineResources = @($DSCStub, $DSCStub2, $TargetResource)

        $result = . $preParseFilePath -PipelineResources $pipelineResources

        @($result).Count | Should -Be 1
        $result.properties['Key1'] | Should -Be 'Value1'
        $result.properties['Key2'] | Should -Be 'ExistingValue'
        $result.properties['Key3'] | Should -Be 'Value3'
    } 
 
    It "Merges complex properties correctly" {

        $resources = @(

            [DSCStub]::New(@{
                name = 'ResourceA'
                merge_with = 'ResourceType/ResourceName/TargetResource'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey1 = 'SubValue1' } }
                type = 'DSCStub'
            })
            [DSCStub]::New(@{
                name = 'ResourceB'
                merge_with = 'ResourceType/ResourceName/ResourceC'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey2 = 'SubValue2' } }
                type = 'DSCStub'                
            })
            [DSCStub]::New(@{
                name = 'ResourceB'
                merge_with = 'ResourceType/ResourceName/ResourceD'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey2 = 'SubValue2' } }
                type = 'DSCStub'                
            })            
            @{
                Name = 'TargetResource'
                Type = 'ResourceType/ResourceName'
                Mergable = $true
                properties = @{ Key2 = @{ SubKey2 = 'SubValue2' } }
            }
            @{
                Name = 'ResourceB'
                Type = 'ResourceType/ResourceName'
                Mergable = $true
                properties = @{ Key3 = 'Value3' }
            }
            @{
                Name = 'ResourceC'
                Type = 'ResourceType/ResourceName'
                Mergable = $true
                properties = @{ Key4 = 'Value4' }
            }
            @{
                Name = 'ResourceD'
                Type = 'ResourceType/ResourceName'
                Mergable = $true
                properties = @{ Key5 = 'Value5' }
            }

        )

        $result = . $preParseFilePath -PipelineResources $resources

        @($result).Count | Should -Be 4

        $result[0].name | Should -Be 'TargetResource'
        $result[0].properties['Key1'] | Should -Be 'Value1'
        $result[0].properties['Key2']['SubKey1'] | Should -Be 'SubValue1'

        $result[1].name | Should -Be 'ResourceB'
        $result[1].properties['Key3'] | Should -Be 'Value3'

        $result[2].name | Should -Be 'ResourceC'
        $result[2].properties['Key4'] | Should -Be 'Value4'
        $result[2].properties['Key2']['SubKey2'] | Should -Be 'SubValue2'
        $result[2].properties['Key1'] | Should -Be 'Value1'

        $result[3].name | Should -Be 'ResourceD'
        $result[3].properties['Key1'] | Should -Be 'Value1'
        $result[3].properties['Key2']['SubKey2'] | Should -Be 'SubValue2'
        $result[3].properties['Key5'] | Should -Be 'Value5'  

    }


}
