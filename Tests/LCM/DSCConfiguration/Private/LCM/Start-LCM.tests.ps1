Describe "Start-LCM Function Tests" -Tag Unit, MockedClass {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Start-LCM.ps1').FullName

        $InvokeCustomTaskPath = (Get-FunctionPath 'Invoke-CustomTask.ps1').FullName
        $InvokePreParseRulesPath = (Get-FunctionPath 'Invoke-PreParseRules.ps1').FullName
        $InvokeFormatTasksPath = (Get-FunctionPath 'Invoke-FormatTasks.ps1').FullName
        $InvokeExpandHashTablePath = (Get-FunctionPath 'Expand-HashTable.ps1').FullName
        $StopTaskProcessingPath = (Get-FunctionPath 'Stop-TaskProcessing.ps1').FullName

        . $preParseFilePath
        . $InvokeCustomTaskPath
        . $InvokePreParseRulesPath
        . $InvokeFormatTasksPath
        . $InvokeExpandHashTablePath
        . $StopTaskProcessingPath

        function Load-Mock {

            return @{
                parameters = @{ 'param1' = 'value1' }
                variables = @{ 'var1' = 'value1' }
                resources = @(
                                @{
                                    type = "Module/Resource"
                                    name = "Resource1"
                                    properties = @{
                                    prop1 = "value1"
                                    }
                                }
                            )
            }
        }

        class DSCConfigurationFile {

            [HashTable]$parameters
            [HashTable]$variables
            [HashTable[]]$resources
            hidden [string]$configurationFilePath
            hidden [bool]$isCompositeResource = $false

            DSCConfigurationFile ([string]$configurationFile, [string]$DSCCompositeResourcePath) {

                if ($null -eq $configurationFile) {
                    throw "Configuration file path is required."
                }

                if ($null -eq $DSCCompositeResourcePath) {
                    throw "Composite resource path is required."
                }

                $result = Load-Mock
                $this.parameters = $result.parameters
                $this.variables = $result.variables
                $this.resources = $result.resources

            }
        }

        $references = @{}
        $variables = @{}
        $parameters = @{}

        Mock -CommandName Write-Host
    
        Mock -CommandName Invoke-DscResource -MockWith {
            param ($Name, $ModuleName, $Method, $Property)
            return @{
                InDesiredState = $Method -eq "Test"
                Message = "Mocked message"
            }
        }
    
        Mock -CommandName Invoke-CustomTask -MockWith {
            param(
                [Parameter(Mandatory=$true)]
                [Object[]]$Tasks,
                [Parameter(Mandatory=$true)]
                [String]$CustomTaskName
            )

            return $pipeline.resources

        }

        Mock -CommandName Invoke-PreParseRules -MockWith {
            param(
                [Parameter(Mandatory=$true)]
                [Object[]]$Tasks
            )

        }

        Mock -CommandName Invoke-FormatTasks -MockWith {
            param(
                [Parameter(Mandatory=$true)]
                [Object[]]$Tasks
            )

            return $Tasks
        }

        Mock -CommandName Expand-HashTable -MockWith {
            param(
                [Parameter(Mandatory=$true)]
                [Hashtable]$InputHashTable
            )

            return $InputHashTable
        }

        Mock -CommandName Export-Csv

        Mock -CommandName Write-Verbose

    }

    BeforeEach {
        # Reset the script-scoped variable before each test
        $script:StopTaskProcessing = $false
    }

    Context "when processing configuration files" {

        It 'should correctly load configuration file' {
            Mock -CommandName Invoke-CustomTask -MockWith { throw "mock error"}
            { Start-LCM -FilePath "test.json" -DSCCompositeResourcePath "C:\CompositeResource" } | Should -Throw "mock error"
        }

    }

    Context "when operating in different modes" {

        BeforeEach {
            $Script:TestDSCResourceCounter = 0
        }

        AfterEach {
            $references.Clear()
        }

        It "should operate in 'Test' mode by default" {
            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $true; Message = "Tested successfully." }
            }

            Start-LCM -FilePath "test.json" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 1
        }

        It "should apply changes in 'Set' mode" {

            Mock -CommandName Invoke-DscResource -MockWith {
                if ($Script:TestDSCResourceCounter -eq 0) {
                    [PSCustomObject]@{ InDesiredState = $false; Message = "Resource set to desired state." }
                    $Script:TestDSCResourceCounter++
                } else {
                    [PSCustomObject]@{ InDesiredState = $true; Message = "Resource set to desired state." }
                }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-LCM -FilePath "test.json" -Mode "Set" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 2
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 1
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter { $Message -like "*Resource set to desired state:*" } -Exactly 1
            
        }

        It "should fail if a resource throws an error attempting to apply changes in 'Set' mode" {
            Mock -CommandName Write-Error
            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -MockWith {
                throw "mock error"
            }

            { Start-LCM -FilePath "test.json" -Mode "Set" -DSCCompositeResourcePath "mock-path" } | Should -Not -Throw
            Assert-MockCalled -CommandName Write-Error -Times 1

        }

        It "should fail if the resource was set however the subsequent test fails" {

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-LCM -FilePath "test.json" -Mode "Set" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 2
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 1
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter { $Message -like "*Failed to set resource to desired state:*" } -Exactly 1
            
        }

        It "should skip tasks when StopTaskProcessing is true" {

            Mock -CommandName Load-Mock -MockWith {
                param ($content)
                return @{
                    parameters = @{
                        param1 = "value1"
                    }
                    variables = @{
                        var1 = "value1"
                    }
                    resources = @(
                        @{
                            type = "Module/Resource"
                            name = "Resource1"
                            postExecutionScript = 'Stop-TaskProcessing'
                            properties = @{
                                prop1 = "value1"
                            }
                        }
                        @{
                            type = "Module/Resource"
                            name = "Resource2"
                            properties = @{
                                prop1 = "value1"
                            }
                        }
                    )
                }
            }

            Start-LCM -FilePath "test.json" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 1
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Get" } -Exactly 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -eq "Tasks Skipped: 1" } -Exactly 1

        }

        It "should skip resources if the condition is met" {
                
            Mock -CommandName Load-Mock -MockWith {
                param ($content)
                return @{
                    parameters = @{
                        param1 = "value1"
                    }
                    variables = @{
                        var1 = "value1"
                    }
                    resources = @(
                        @{
                            type = "Module/Resource"
                            name = "Resource1"
                            properties = @{
                                prop1 = "value1"
                            }
                            condition = '1 -ne 1'
                        }
                        @{
                            type = "Module/Resource"
                            name = "Resource2"
                            properties = @{
                                prop2 = "value2"
                            }
                            condition = '1 -eq 1'
                        }
                    )
                }
            }

            Start-LCM -FilePath "test.json" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Property.prop1 -eq "value1" } -Exactly 0
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Property.prop2 -eq "value2" } -Exactly 2

        }       

    }

    Context "when handling report paths" {

        BeforeAll {
            Mock -CommandName Get-Content -MockWith { '{"parameters": {}, "variables": {}, "resources": []}' }
            $references.Clear()
        }

        AfterAll {
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Total Tasks Executed*" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Tasks Passed*" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Tasks Failed*" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Tasks Skipped*" } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -like "*Total Tasks*" } -Times 1
        }

        It "should generate a report if ReportPath is specified" {
            Mock -CommandName Export-Csv -MockWith {}

            Start-LCM -FilePath "test.json" -ReportPath "C:\Reports" -DSCCompositeResourcePath "mock-path" 
            Assert-MockCalled -CommandName Export-Csv -Exactly 1
        }

        It "should not generate a report if ReportPath is not specified" {
            Mock -CommandName Export-Csv -MockWith {}

            Start-LCM -FilePath "test.json" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Export-Csv -Exactly 0
        }
    }

    Context "error handling and edge cases" {

        It "should handle invalid Mode parameter" {
            { Start-LCM -FilePath "test.json" -Mode "Invalid" -DSCCompositeResourcePath "mock-path" } | Should -Throw
        }

        It "should print a non-terminating error when the LCM fails to set a resource" {

            Mock -CommandName Write-Error -ParameterFilter { $Message -like "*Failed to apply changes with 'Set' method*" } -Verifiable
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Verifiable -MockWith {
                throw "mock error"
            }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith {
                @{
                    InDesiredState = $false 
                }
            } -Verifiable
            Mock -CommandName Get-Content -MockWith { "---\nparameters: {}\nvariables: {}\nresources: []" }

            { Start-LCM -FilePath "test.json" -Mode "Set" -DSCCompositeResourcePath "mock-path" } | Should -Not -Throw
            Should -InvokeVerifiable

        }
    }
    
}    
    