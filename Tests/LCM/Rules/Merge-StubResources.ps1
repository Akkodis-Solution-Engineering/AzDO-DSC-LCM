# Import the module containing Merge-StubResources if it's in a separate file.
# . "$PSScriptRoot\Path\To\YourModule.psm1"

Describe "Merge-StubResources" -Tag Unit, LCM, Rules, Sort {

    BeforeAll {

        $DSCEnumDSCResourceType = (Get-FunctionPath 'DSCResourceType.ps1').FullName

        $DSCConfigurationFile = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCYAMLResource = (Get-FunctionPath '002.DSCYAMLResource.ps1').FullName
        $DSCStub = (Get-FunctionPath '003.DSCStub.ps1').FullName
        $DSCCompositeResource = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Merge-StubResources.ps1').FullName
        $joinPropertiesFilePath = (Get-FunctionPath 'mergeProperties.ps1').FullName

        . $DSCEnumDSCResourceType

        . $DSCConfigurationFile
        . $DSCBaseResource
        . $DSCYAMLResource
        . $DSCStub
        . $DSCCompositeResource
        . $joinPropertiesFilePath

        # Define mock DSCStub and resource objects for testing
        $DSCStub = [DSCStub]::New(@{ 
            name = 'ResourceA'
            merge_with = 'TargetResource'
            properties = @{ Key1 = 'Value1' }
        })
        $TargetResource = @{ Name = 'TargetResource'; properties = @{ Key2 = 'ExistingValue' } }

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

    It "Warns when a stub resource's target is not found" {
        Mock Write-Warning
        $pipelineResources = @($DSCStub)

        { . $preParseFilePath -PipelineResources $pipelineResources } | Should -Not -Throw
        Assert-MockCalled Write-Warning -Exactly 1
    }

    It "Does not merge properties when a stub resource's target is not found and there are no other resources" {
        Mock Write-Warning
        $pipelineResources = @($DSCStub)

        $result = . $preParseFilePath -PipelineResources $pipelineResources

        @($result).Count | Should -Be 0
        Assert-MockCalled Write-Warning -Exactly 1
    }

    It "Does not merge properties when a stub resource's target is not found and there are other resources" {
        Mock Write-Warning

        $DSCStub = [DSCStub]::New(@{ 
            name = 'ResourceA'
            merge_with = 'NonExistentResource'
            properties = @{ Key1 = 'Value1' }
        })
        $pipelineResources = @($DSCStub, $TargetResource)

        $result = . $preParseFilePath -PipelineResources $pipelineResources

        @($result).Count | Should -Be 1
        $result.properties['Key1'] | Should -Be 'Value1'
        Assert-MockCalled Write-Warning -Exactly 1
    }

    It "Merge multiple sub resources with the same target resource" {
        $DSCStub2 = [DSCStub]::New(@{ 
            name = 'ResourceB'
            merge_with = 'TargetResource'
            properties = @{ Key3 = 'Value3' }
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
                merge_with = 'TargetResource'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey1 = 'SubValue1' } }
            })
            [DSCStub]::New(@{
                name = 'ResourceB'
                merge_with = 'ResourceC'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey2 = 'SubValue2' } }
            })
            [DSCStub]::New(@{
                name = 'ResourceB'
                merge_with = 'ResourceD'
                properties = @{ Key1 = 'Value1'; Key2 = @{ SubKey2 = 'SubValue2' } }
            })            
            @{
                Name = 'TargetResource'
                properties = @{ Key2 = @{ SubKey2 = 'SubValue2' } }
            }
            @{
                Name = 'ResourceB'
                properties = @{ Key3 = 'Value3' }
            }
            @{
                Name = 'ResourceC'
                properties = @{ Key4 = 'Value4' }
            }
            @{
                Name = 'ResourceD'
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
