Describe "Test-ResourcesForIncorrectProperties" -Tag Unit, LCM, Rules, PreParse {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Test-ResourcesForIncorrectProperties.ps1').FullName
        . $preParseFilePath

        # Mock Get-DscResource for testing purposes
        Mock -CommandName Get-DscResource -MockWith {
            @{
                Name = 'MyResourceType'
                Properties = @(
                    [PSCustomObject]@{ Name = 'Property1'; PropertyType = 'String'; IsMandatory = $true; Values = @('Value1', 'Value2') },
                    [PSCustomObject]@{ Name = 'Property2'; PropertyType = 'String'; IsMandatory = $false; Values = @() }
                )
            }
        }

        Mock -CommandName Write-Host

    } 

    It "Should throw error if 'properties' key does not exist" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
            }
        )
        
        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*'Properties' key does not exist for resource:*" }

    }

    It "Should throw error if 'name' key does not exist" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                properties = @{
                    Property1 = 'Value1'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*'Name' key does not exist for resource:*" }
    }

    It "Should pass if all required keys exist and properties are correct" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = 'Value1'
                    Property2 = 'Value2'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources -Verbose } | Should -Not -Throw
    }

    It "Should throw error if resource is not found" {
        Mock -CommandName Get-DscResource -MockWith { $null }

        $resources = @(
            [PSCustomObject]@{
                type = 'Module/NonExistentResourceType'
                name = 'NonExistentResource'
                properties = @{
                    Property1 = 'Value1'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Resource * was not found in module*" }

    }

    It "Should throw error if mandatory property is null" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = $null
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*is mandatory in resource*" }

    }

    It "Should throw error if property value does not match selected values" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = 'InvalidValue'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*does not match the selected values in resource*" }
    }

    It "Should throw error if property value is not of correct type" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = 123
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*does not match the selected values in resource*" }
    }

    It "Should not skip the property if it's a scriptblock" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = 'Value1'
                    Property2 = '{scriptblock}'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Not -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*is a caculated variable in resource*" } -Exactly 0

    }

    It "Should skip the property if it's a caculated property" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = 'Value1'
                    Property2 = '$($mock_variable)'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Not -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*is a caculated variable in resource*" }

    }

    It "Should skip both caculated properties" {
        $resources = @(
            [PSCustomObject]@{
                type = 'Module/MyResourceType'
                name = 'MyResource'
                properties = @{
                    Property1 = '$($mock_variable)'
                    Property2 = '$($mock_variable)'
                }
            }
        )

        { . $preParseFilePath -PipelineResources $resources } | Should -Not -Throw
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*is a caculated variable in resource*" } -Exactly 2

    }

}
