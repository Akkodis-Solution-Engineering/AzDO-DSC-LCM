# Import the necessary module for the DSCConfigurationFile class

Describe "DSCConfigurationFile Class Tests" -Tag Unit {
    
    BeforeAll {
        # Mock functions used within the class

        $DSCConfigurationFile = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        . $DSCConfigurationFile

        function ConvertTo-Resource { param($task, $compositeResourcePath) return @(@{
            Name = "resource1"
            Type = "resourceType"
            Properties = @{
                Property1 = "value1"
                Property2 = "value2"
            }
        }) }
        function GetParameterValues { param($Source) return @{
            param1 = "value1"
            param2 = "value2"
        } }
        function SetVariables { param($Source) return @{
            var1 = "value1"
            var2 = "value2"
        } }

        # Path to a mock configuration file

        $mockYamlFile = Join-Path -Path $TestDrive -ChildPath "config.yaml"
        $mockJsonFile = Join-Path -Path $TestDrive -ChildPath "config.json"

        # Create a temporary YAML file for testing
        New-Item -Path $mockYamlFile -ItemType File -Force | Out-Null
        Set-Content -Path $mockYamlFile -Value @"
parameters:
  param1: value1
variables:
  var1: value1
resources:
  - name: resource1
"@

        # Create a temporary JSON file for testing
        New-Item -Path $mockJsonFile -ItemType File -Force | Out-Null
        Set-Content -Path $mockJsonFile -Value '{"parameters": {"param1": "value1"}, "variables": {"var1": "value1"}, "resources": [{"name": "resource1"}]}'

    }

    AfterAll {
        # Clean up the mock files
        Remove-Item -Path $mockYamlFile -Force
        Remove-Item -Path $mockJsonFile -Force
    }

    Context "Constructor Tests" {
        It "Should create an instance with YAML file" {
            $configFile = [DSCConfigurationFile]::new($mockYamlFile)
            $configFile.isCompositeResource = $true
            
            $configFile | Should -Not -BeNullOrEmpty
            $configFile.isCompositeResource | Should -Be $true
        }

        It "Should create an instance with JSON file and composite path" {
            $configFile = [DSCConfigurationFile]::new($mockJsonFile, "mockPath\to\composite")
            $configFile | Should -Not -BeNullOrEmpty
            $configFile.compositeResourcePath | Should -Be "mockPath\to\composite"
        }
    }

    Context "Load Method Tests" {
        It "Should load YAML configuration correctly" {
            $configFile = [DSCConfigurationFile]::new($mockYamlFile)
            $configFile.load($mockYamlFile)

            $configFile.configurationFilePath | Should -Be $mockYamlFile
            $configFile.parameters | Should -Not -BeNullOrEmpty
            $configFile.variables | Should -Not -BeNullOrEmpty
            $configFile.resources | Should -Not -BeNullOrEmpty
        }

        It "Should load JSON configuration correctly" {
            $configFile = [DSCConfigurationFile]::new($mockJsonFile)
            $configFile.load($mockJsonFile)

            $configFile.configurationFilePath | Should -Be $mockJsonFile
            $configFile.parameters | Should -Not -BeNullOrEmpty
            $configFile.variables | Should -Not -BeNullOrEmpty
            $configFile.resources | Should -Not -BeNullOrEmpty
        }

        It "Should throw error for unknown file extension" {
            { [DSCConfigurationFile]::new("\mockfilepath\badfile.ext") } | Should -Throw "*Unknown file extension*"
        }
    }

    Context "when parameters, variables, resources are null" {

        BeforeAll {
            Mock ConvertTo-Resource { param($task, $compositeResourcePath) return $null }
            Mock GetParameterValues { param($Source) return $null }
            Mock SetVariables { param($Source) return $null }
        }

        It "Should return null for parameters, variables, resources" {
            $configFile = [DSCConfigurationFile]::new($mockYamlFile)
            $configFile.parameters | Should -BeNullOrEmpty
            $configFile.variables | Should -BeNullOrEmpty
            $configFile.resources | Should -BeNullOrEmpty
        }

    }


}
