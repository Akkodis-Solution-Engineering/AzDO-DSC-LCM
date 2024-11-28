
Describe "DSCCompositeResource Class Tests" -Tag Unit {
    
    BeforeAll {
        
        # Mocking the DSCBaseResource class
        $DSCConfigurationFile = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCCompositeResource = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName
                
        $mergePropertiesPath = (Get-FunctionPath 'mergeProperties.ps1').FullName

        . $DSCConfigurationFile
        . $DSCBaseResource
        . $DSCCompositeResource

        . $mergePropertiesPath

    }

    Context "Constructor Tests" {
        BeforeAll {
            # Setup a temporary directory for testing
            $testDirectory = Join-Path -Path $TestDrive -ChildPath "TestCompositeResources"
            if (-not (Test-Path -LiteralPath $testDirectory)) {
                New-Item -ItemType Directory -Path $testDirectory | Out-Null
            }

            $task = @{
                name = "TestTask"
                type = "TestType"
                properties = @{
                    key = "value"
                }
            }

        }

        AfterAll {
            # Cleanup the temporary directory after tests
            Remove-Item -Recurse -Force -Path $testDirectory
        }

        It "Should throw error if the composite resource file does not exist" {
            $resourceName = "NonExistentResource"
            { [DSCCompositeResource]::new($resourceName, $testDirectory, $task) } | Should -Throw "*Error. The composite resource cannot be found. Please check that the file is named correctly and try again.*"
        }

        It "Should initialize all properties correctly when the composite resource file exists" {
            $resourceName = "ExistingResource"
            $linkedFileName = Join-Path $testDirectory "$resourceName.yml"

            # Create a mock composite resource file
            New-Item -ItemType File -Path $linkedFileName | Out-Null

            $compositeResource = [DSCCompositeResource]::new($resourceName, $testDirectory, $task)

            $compositeResource.name | Should -Be $task.name
            $compositeResource.type | Should -Be $task.type
            $compositeResource.properties | Should -Be $task.properties
            $compositeResource.linkedFileName | Should -Be $linkedFileName
            $compositeResource.resource.configurationFilePath | Should -Be $linkedFileName
        }
        
    }
}
