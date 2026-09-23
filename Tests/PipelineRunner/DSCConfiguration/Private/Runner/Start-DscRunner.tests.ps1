Describe "Start-DscRunner Function Tests" -Tag Unit, MockedClass {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Start-DscRunner.ps1').FullName

        $ExecutionMethod = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName

        $InvokeCustomTaskPath = (Get-FunctionPath 'Invoke-CustomTask.ps1').FullName
        $InvokePreParseRulesPath = (Get-FunctionPath 'Invoke-PreParseRules.ps1').FullName
        $InvokeFormatTasksPath = (Get-FunctionPath 'Invoke-FormatTasks.ps1').FullName
        $InvokeExpandHashTablePath = (Get-FunctionPath 'Expand-HashTable.ps1').FullName
        $StopTaskProcessingPath = (Get-FunctionPath 'Stop-TaskProcessing.ps1').FullName
        $GetDefaultValuesPath = (Get-FunctionPath 'GetDefaultValues.ps1').FullName
        $SetVariablesPath = (Get-FunctionPath 'SetVariables.ps1').FullName
        $ConvertToPipelineTaskPath = (Get-FunctionPath 'ConvertTo-PipelineTask.ps1').FullName
        $DSCBaseResourcePath = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSCResourcePath = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $ExpandParametersPath = (Get-FunctionPath 'Expand-Parameters.ps1').FullName
        $ExpandParameterInArrayPath = (Get-FunctionPath 'Expand-ParameterInArray.ps1').FullName
        $DscMethodResultPath = (Get-FunctionPath '005.DscMethodResult.ps1').FullName
        $ConvertToDscMethodResultPath = (Get-FunctionPath 'ConvertTo-DscMethodResult.ps1').FullName
        $InvokeActionPath = (Get-FunctionPath 'Invoke-Action.ps1').FullName
        $InvokeEngineActionPath = (Get-FunctionPath 'Invoke-EngineAction.ps1').FullName
        $ConvertToNormalizedConditionExpressionPath = (Get-FunctionPath 'ConvertTo-NormalizedConditionExpression.ps1').FullName
        $AssertSafeConditionExpressionPath = (Get-FunctionPath 'Assert-SafeConditionExpression.ps1').FullName

        . $ExecutionMethod
        # ConvertTo-PipelineTask type-binds its -Resource parameter to [DSC_Resource]; load the
        # real class chain (not a mock) so Start-DscRunner's Custom-rule pipeline can produce
        # genuine DSC_Resource instances for it to project.
        . $DSCBaseResourcePath
        . $DSCResourcePath
        . $ExpandParameterInArrayPath
        . $ExpandParametersPath
        . $DscMethodResultPath
        . $ConvertToDscMethodResultPath
        . $InvokeActionPath
        . $InvokeEngineActionPath
        . $ConvertToNormalizedConditionExpressionPath
        . $AssertSafeConditionExpressionPath
        . $preParseFilePath
        . $InvokeCustomTaskPath
        . $InvokePreParseRulesPath
        . $InvokeFormatTasksPath
        . $InvokeExpandHashTablePath
        . $StopTaskProcessingPath
        . $GetDefaultValuesPath
        . $SetVariablesPath
        . $ConvertToPipelineTaskPath

        function Load-Mock {

            return @{
                parameters = @{ 'param1' = 'value1' }
                variables = @{ 'var1' = 'value1' }
                resources = @(
                                @{
                                    executionMethodOverride = 'None'
                                    type                    = "Module/Resource"
                                    name                    = "Resource1"
                                    properties              = @{
                                                                prop1 = "value1"
                                                            }
                                }
                            )
            }
        }

        enum ExecutionMethod {
            None
            Test
            Set
        }

        class DSCConfigurationFile {

            [HashTable]$parameters
            [HashTable]$variables
            [HashTable[]]$resources
            hidden [string]$configurationFilePath
            hidden [bool]$isCompositeResource = $false
            [ExecutionMethod]$executionMethodOverride = 'None'

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

        # Invoke-Action resolves Actions/<Hook>/<Name>.ps1 via (Get-Module 'DSC.PipelineRunner.Akkodis').ModuleBase.
        # These tests dot-source functions rather than importing the module, so that lookup
        # returns nothing; mock it to point at the real repo root (Actions/Engine/DscV2.ps1
        # lives there) so the engine dispatch runs for real and reaches the Invoke-DscResource
        # mocks below, same as Invoke-CustomTask.tests.ps1 does for Pipeline Rules.
        Mock -CommandName Get-Module -MockWith { return (
            @{
                ModuleBase = $Global:RepositoryRoot
            })
        }

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
                [Object[]]$Tasks,
                [Object]$Settings
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
            { Start-DscRunner -FilePath "test.json" -DSCCompositeResourcePath "C:\CompositeResource" -ConfigurationMode 'audit' } | Should -Throw "mock error"
        }

    }

    Context "when operating in different modes" {

        BeforeEach {
            $global:TestDSCResourceCounter = 0
        }

        AfterEach {
            $references.Clear()
        }

        It "Should apply no changes in 'Audit' mode when resource is in desired state" {

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $true; Message = "No action taken." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Audit" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 1
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 0

        }

        It "Should apply no changes in 'Audit' mode when resource is in not in the desired state" {

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "No action taken." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Audit" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 1
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 0

        }


        It "should apply changes in 'Enforce' mode" {

            Mock -CommandName Invoke-DscResource -MockWith {
                if ($global:TestDSCResourceCounter -eq 0) {
                    [PSCustomObject]@{ InDesiredState = $false; Message = "Resource set to desired state." }
                    $global:TestDSCResourceCounter++
                } else {
                    [PSCustomObject]@{ InDesiredState = $true; Message = "Resource set to desired state." }
                }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 2
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 1
            
        }

        It "should apply changes in 'Enforce' mode, but not check again if the change was successful" {

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Resource set to desired state." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "ApplyOnly" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 1
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 1

        }

        It "should fail if a resource throws an error attempting to apply changes in 'Enforce' mode" {
            Mock -CommandName Write-Error
            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -MockWith {
                throw "mock error"
            }

            { Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path" } | Should -Not -Throw
            Assert-MockCalled -CommandName Write-Error -Times 1

        }

        It "should fail if the resource was set however the subsequent test fails" {

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            } -ParameterFilter { $Method -eq "Test" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" }

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Test" } -Exactly 2
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq "Set" } -Exactly 1

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
                            executionMethodOverride = 'None'
                        }
                        @{
                            type = "Module/Resource"
                            name = "Resource2"
                            properties = @{
                                prop1 = "value1"
                            }
                            executionMethodOverride = 'None'
                        }
                    )
                }
            }

            Start-DscRunner -FilePath "test.json" -DSCCompositeResourcePath "mock-path" -ConfigurationMode "Enforce"

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

            Start-DscRunner -FilePath "test.json" -DSCCompositeResourcePath "mock-path" -ConfigurationMode "Enforce"

            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Property.prop1 -eq "value1" } -Exactly 0
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Property.prop2 -eq "value2" } -Exactly 2

        }        

    }

    Context "when handling different execution methods" {

        BeforeAll {
            Mock -CommandName Get-Content -MockWith { '{"parameters": {}, "variables": {}, "resources": []}' }
            $references.Clear()
        }

        It "should handle 'None' execution method correctly" {

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
                            executionMethodOverride = 'None'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $true; Message = "No action taken." }
            }

            Mock -CommandName Write-Verbose

            Start-DscRunner -FilePath "test.json" -DSCCompositeResourcePath "mock-path" -ConfigurationMode "Enforce"

            Assert-MockCalled -CommandName Invoke-DscResource -Exactly 2
            Assert-MockCalled -CommandName Write-Verbose -Exactly 0 -ParameterFilter { $Message -like "Using custom execution method: None" }
        }

        It "should handle 'Test' execution method correctly" {

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
                            executionMethodOverride = 'Test'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $true; Message = "No action taken." }
            }

            Mock -CommandName Write-Verbose

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -Exactly 2
        }

        It "should handle 'Set' execution method correctly" {

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
                            executionMethodOverride = 'Set'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -MockWith {
                [PSCustomObject]@{ InDesiredState = $true; Message = "No action taken." }
            }

            Mock -CommandName Write-Verbose

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path"

            Assert-MockCalled -CommandName Invoke-DscResource -Exactly 2
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
            Mock -CommandName Export-Csv

            Start-DscRunner -FilePath "test.json" -ReportPath "C:\Reports" -DSCCompositeResourcePath "mock-path" -ConfigurationMode "Enforce"
            Assert-MockCalled -CommandName Export-Csv -Times 1
        }

        It "should not generate a report if ReportPath is not specified" {
            Mock -CommandName Export-Csv

            Start-DscRunner -FilePath "test.json" -DSCCompositeResourcePath "mock-path" -ConfigurationMode "Enforce"

            Assert-MockCalled -CommandName Export-Csv -Exactly 0
        }
    } 

    Context "error handling and edge cases" {

        It "should print a non-terminating error when the engine fails to set a resource" {

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

            { Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path" } | Should -Not -Throw
            Should -InvokeVerifiable

        }

        It "should stop all subsequent tasks when a Set fails and -ContinueOnError is NOT set" {

            Mock -CommandName Load-Mock -MockWith {
                return @{
                    parameters = @{}
                    variables  = @{}
                    resources  = @(
                        @{ type = "Module/Resource"; name = "Resource1"; properties = @{ p = 1 }; executionMethodOverride = 'None' }
                        @{ type = "Module/Resource"; name = "Resource2"; properties = @{ p = 2 }; executionMethodOverride = 'None' }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { throw "mock set error" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Get' } -MockWith { @{} }
            Mock -CommandName Write-Error

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path"

            # Resource1 fails Set → StopTaskProcessing → Resource2 is skipped
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -eq "Tasks Skipped: 1" } -Exactly 1
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter { $Message -like "Skipping resource due to 'Stop-TaskProcessing' being called*" } -Exactly 1

        }

    }

    Context "when using -ContinueOnError" {

        BeforeEach {
            $references.Clear()
            $script:StopTaskProcessing = $false
        }

        It "should continue processing when Set fails and -ContinueOnError is set" {

            Mock -CommandName Load-Mock -MockWith {
                return @{
                    parameters = @{}
                    variables  = @{}
                    resources  = @(
                        @{ type = "Module/Resource"; name = "Resource1"; properties = @{ p = 1 }; executionMethodOverride = 'None' }
                        @{ type = "Module/Resource"; name = "Resource2"; properties = @{ p = 2 }; executionMethodOverride = 'None' }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { throw "mock set error" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Get' } -MockWith { @{} }
            Mock -CommandName Write-Error

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path" -ContinueOnError

            # Both resources attempted (Resource2 is not a dependent of Resource1)
            Assert-MockCalled -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -Exactly 2

        }

        It "should skip dependent resources when their dependency fails and -ContinueOnError is set" {

            Mock -CommandName Load-Mock -MockWith {
                return @{
                    parameters = @{}
                    variables  = @{}
                    resources  = @(
                        @{
                            type = "Module/Resource"; name = "Resource1"
                            properties = @{ p = 1 }; executionMethodOverride = 'None'
                        }
                        @{
                            type = "Module/Resource"; name = "Resource2"
                            dependsOn = "Module/Resource/Resource1"
                            properties = @{ p = 2 }; executionMethodOverride = 'None'
                        }
                        @{
                            type = "Module/Resource"; name = "Resource3"
                            properties = @{ p = 3 }; executionMethodOverride = 'None'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { throw "mock set error" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Get' } -MockWith { @{} }
            Mock -CommandName Write-Error

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path" -ContinueOnError

            # Resource2 (depends on Resource1) is SKIPPED; Resource3 (no dep on Resource1) continues
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter {
                $Message -like "Skipping resource*dependency 'Module/Resource/Resource1' failed*"
            } -Exactly 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -eq "Tasks Skipped: 1" } -Exactly 1

        }

        It "should cascade dependency failure to transitive dependents" {

            Mock -CommandName Load-Mock -MockWith {
                return @{
                    parameters = @{}
                    variables  = @{}
                    resources  = @(
                        @{
                            type = "Module/Resource"; name = "A"
                            properties = @{ p = 1 }; executionMethodOverride = 'None'
                        }
                        @{
                            type = "Module/Resource"; name = "B"
                            dependsOn = "Module/Resource/A"
                            properties = @{ p = 2 }; executionMethodOverride = 'None'
                        }
                        @{
                            type = "Module/Resource"; name = "C"
                            dependsOn = "Module/Resource/B"
                            properties = @{ p = 3 }; executionMethodOverride = 'None'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith {
                [PSCustomObject]@{ InDesiredState = $false; Message = "Not in desired state." }
            }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { throw "mock set error" }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Get' } -MockWith { @{} }
            Mock -CommandName Write-Error

            Start-DscRunner -FilePath "test.json" -ConfigurationMode "Enforce" -DSCCompositeResourcePath "mock-path" -ContinueOnError

            # A fails → B is SKIPPED (depends on A) → C is SKIPPED (depends on B, which is in failedResources)
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter {
                $Message -like "Skipping resource*dependency 'Module/Resource/A' failed*"
            } -Exactly 1
            Assert-MockCalled -CommandName Write-Verbose -ParameterFilter {
                $Message -like "Skipping resource*dependency 'Module/Resource/B' failed*"
            } -Exactly 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Message -eq "Tasks Skipped: 2" } -Exactly 1

        }

    }

}
