
Describe "DSCCompositeResource Class Tests" {
    
    BeforeAll {
        
        # Mocking the DSCBaseResource class
        $enumsResource = (Get-FunctionPath 'DSCResourceType.ps1').FullName

        $DSCConfigurationFile = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        $DSCBaseResource = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCCompositeResource = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName
        
        
        $mergePropertiesPath = (Get-FunctionPath 'mergeProperties.ps1').FullName

        . $enumsResource
        . $DSCConfigurationFile
        . $DSCBaseResource
        . $DSCCompositeResource

        . $mergePropertiesPath

    }

    Context "Constructor Tests" {
        BeforeAll {
            # Setup a temporary directory for testing
            $testDirectory = Join-Path -Path (Get-Location) -ChildPath "TestCompositeResources"
            if (-not (Test-Path -LiteralPath $testDirectory)) {
                New-Item -ItemType Directory -Path $testDirectory | Out-Null
            }
        }

        AfterAll {
            # Cleanup the temporary directory after tests
            Remove-Item -Recurse -Force -Path $testDirectory
        }

        It "Should throw error if the composite resource file does not exist" {
            $resourceName = "NonExistentResource"
            { [DSCCompositeResource]::new($resourceName, $testDirectory) } | Should -Throw "[DSCCompositeResource] Error. The composite resource cannot be found. Please check that the file is named correctly and try again. FilePath: $(Join-Path $testDirectory "$resourceName.yml")"
        }

        It "Should initialize all properties correctly when the composite resource file exists" {
            $resourceName = "ExistingResource"
            $linkedFileName = Join-Path $testDirectory "$resourceName.yml"

            # Create a mock composite resource file
            New-Item -ItemType File -Path $linkedFileName | Out-Null

            $compositeResource = [DSCCompositeResource]::new($resourceName, $testDirectory)

            $compositeResource.linkedFileName | Should -Be $linkedFileName
            $compositeResource.type | Should -Be [DSCResourceType]::Composite
            $compositeResource.resource.filePath | Should -Be $linkedFileName
        }
    }
}
