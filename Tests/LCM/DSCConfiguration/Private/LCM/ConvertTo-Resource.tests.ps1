
Describe "ConvertTo-Resource" -Tag Unit, LCM, MockedClass {

    BeforeAll {
        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'ConvertTo-Resource.ps1').FullName

        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $DSCStub = (Get-FunctionPath '003.DSCStub.ps1').FullName
        $DSCCompositeResource = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName

        class DSCConfigurationFile {
            [string]$mock = "Mock"
            DSCConfigurationFile ([string]$filePath, [bool]$isComposite) {    
            }
        }

        . $DSCBaseResource
        . $DSC_Resource
        . $DSCStub
        . $DSCCompositeResource

        . $preParseFilePath

        Mock Get-Content -MockWith { return "Mock" }

    }

    It "Should return a DSCCompositeResource when the task type is composite" {

        Mock -CommandName Test-Path -MockWith { $true }
        
        $task = @{
            type = 'composite\MyCompositeResource'
            name = 'mock'
            properties = @{
                Property1 = 'Value1'
            }
        }

        $result = $task | ConvertTo-Resource -compositeResourcePath "SomePath"
        $result.type = 'Composite'
        
    }

    It "Should return a DSCStub when the task has MergeWith property" {
        
        $task = @{
            type = 'module\SomeType'
            merge_with = 'OtherResource'
            name = 'mock'
            properties = @{
                Property1 = 'Value1'
            }
        }

        $result = $task | ConvertTo-Resource -compositeResourcePath "SomePath"
        $result[0].GetType().Name | Should -Be "DSCStub"
    }

    It "Should return a DSCResource for all other tasks" {
        $task = @{
            type = 'StandardType'
            name = 'mock'
            properties = @{
                Property1 = 'Value1'
            }
        }
        $result = $task | ConvertTo-Resource -compositeResourcePath "SomePath"
        $result[0].GetType().Name | Should -Be "DSC_Resource"
    }

    It "Should handle multiple tasks from pipeline" {

        Mock -CommandName Test-Path -MockWith { $true }

        $tasks = @(
            @{
                type = 'composite\MyCompositeResource'
                name = 'mock'
                properties = @{
                    Property1 = 'Value1'
                }                
            }
            @{
                type = 'module\SomeType'
                merge_with = 'OtherResource'
                name = 'mock'
                properties = @{
                    Property1 = 'Value1'
                }
            }
            @{
                type = 'StandardType'
                name = 'mock'
                properties = @{
                    Property1 = 'Value1'
                }
            }
        )

        $results = $tasks | ConvertTo-Resource -compositeResourcePath "SomePath"
        
        $results.Count | Should -Be 3

        $results[0].GetType().Name | Should -Be "DSCCompositeResource"
        $results[1].GetType().Name | Should -Be "DSCStub"
        $results[2].GetType().Name | Should -Be "DSC_Resource"
    }

}
