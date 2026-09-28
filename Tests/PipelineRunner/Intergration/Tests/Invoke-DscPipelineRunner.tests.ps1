
Describe "Invoke-DscPipelineRunner Intergration Tests" -Tag Integration {

    AfterAll {
        Restore-ProcessEnvironment -Snapshot $script:ProcessEnvironment
    }

    BeforeAll {
        # Suites share one process; see Save-ProcessEnvironment for why this matters.
        $script:ProcessEnvironment = Save-ProcessEnvironment
        # Perform the latest build. This will ensure that the latest version of the module is loaded.
        . .\Build.ps1 -Tasks Build

        # Load the module into memory
        $modulePath = Get-ModulePath

        # Load the Enums First
        Get-ChildItem -LiteralPath $modulePath.EnumsDirectory -Recurse -File -Include *.ps1 | ForEach-Object { . $_.FullName }
        # Load the Classes First
        Get-ChildItem -LiteralPath $modulePath.ClassesDirectory -Recurse -File -Include *.ps1 | Where-Object { . $_.FullName }
        # Load the Public Functions
        Get-ChildItem -LiteralPath $modulePath.PublicFunctionsDirectory -Recurse -File -Include *.ps1 | Where-Object { . $_.FullName }
        # Load the Private Functions
        Get-ChildItem -LiteralPath $modulePath.PrivateFunctionsDirectory -Recurse -File -Include *.ps1 | Where-Object { . $_.FullName }

        # Load the mock DSC module
        Install-Dependencies

        # Copy the test cases to the temp drive
        Copy-TestCasesToTempDrive
        
        New-Item (Join-Path $TestDrive -ChildPath 'Output') -ItemType Directory -Force
        New-Item (Join-Path $TestDrive -ChildPath 'Reports') -ItemType Directory -Force
        New-Item (Join-Path $TestDrive -ChildPath 'Cache') -ItemType Directory -Force

        $TempTestDrive = $TestDrive

        # Set the environment variable
        $ENV:AZDODSC_CACHE_DIRECTORY = Join-Path $TestDrive -ChildPath 'Cache'

        # Get-DscResource needs Windows' libmi. Elsewhere, describe the mock AzureDevOpsDsc
        # module's resources from its class definitions.
        if (-not $IsWindows) {
            $script:MockResourceModulePath = Join-Path $Global:RepositoryRoot 'Tests/PipelineRunner/Intergration/Resources/Modules/AzureDevOpsDsc'
            Mock -CommandName Get-DscResource -MockWith {
                Get-DscResourceFromClassDefinition -Path $script:MockResourceModulePath -Name @($PesterBoundParameters['Name'])[0]
            }
        }

        # Mock List
        Mock -CommandName Clone-Repository -MockWith { return Join-Path $TestDrive -ChildPath 'Configuration' }
        Mock -CommandName New-AzDoAuthenticationProvider -MockWith { return $null }
        Mock -CommandName Invoke-DscResource -ParameterFilter {
            $Method -eq 'Get'
        } -MockWith { return @{} }
        Mock -CommandName Invoke-DscResource -ParameterFilter {
            $Method -eq 'Set'
        } -MockWith { return @{} }
        
        # Mock Sucessfull Configuration Application
        Mock -CommandName Invoke-DscResource -ParameterFilter {
            $Method -eq 'Test'
        } -MockWith { 
            return @{ 
                InDesiredState = $true
            }
        }

        $params = @{
            AzureDevopsOrganizationName = 'mock-org'
            exportConfigDir = Join-Path $TestDrive -ChildPath 'Output'
            JITToken = 'mock'
            ConfigurationMode = 'Audit'
            ConfigurationSourcePath = $null
        }

    }

    Context "When running Invoke-DscPipelineRunner with a valid configuration" {

        BeforeAll {
            Import-Module 'DSC.PipelineRunner.Akkodis'
        }

        BeforeEach {
            # Reset the parameters
            $references = @{}
            $variables = @{}
            $parameters = @{}

            Mock -CommandName Write-Host
            Mock -CommandName Write-Error
            Mock -CommandName Write-Verbose
            Mock -CommandName Write-Warning

        }

        AfterEach {
            $params.ConfigurationMode = 'Audit'
        }

        It "Should not throw any errors when using 'StandardResources' test case" {
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw
        }

        It "Should not throw any errors when using 'StandardResources' test case with no ConfigurationMode parameter specified" {
            $params.Remove('ConfigurationMode')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw
        }

        It "Should not throw any errors when using 'StandardResources' test case" {
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw
        }

        It "Should not throw any errors when using 'StubResources' test case" {
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StubResources'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw
        }

        It "Should not throw any resource errors when 'StandardResources' test case" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'

            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Status -eq 'SKIP' } | Should -BeNullOrEmpty
            $report | Where-Object { $_.Status -eq 'FAIL' } | Should -BeNullOrEmpty
        }

        It "Should not throw any resource errors when using 'StubResources' test case" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StubResources'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Status -eq 'SKIP' } | Should -BeNullOrEmpty
            $report | Where-Object { $_.Status -eq 'FAIL' } | Should -BeNullOrEmpty            
        }

        It "Should skip the resource when using conditional property" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\ConditionalProperty'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Status -eq 'SKIP' } | Should -HaveCount 1
            $report | Where-Object { $_.Status -eq 'FAIL' } | Should -BeNullOrEmpty
        }

        It "Should skip all tests with 'StopProcessing' is used" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StopProcessing'
            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Status -eq 'SKIP' } | Should -HaveCount 3
            $report | Where-Object { $_.Status -eq 'OK' } | Should -HaveCount 1
            $report | Where-Object { $_.Status -eq 'FAIL' } | Should -BeNullOrEmpty
        }

    }

    Context "When running Invoke-DscPipelineRunner with a custom execution method" {

        BeforeAll {
            Import-Module 'DSC.PipelineRunner.Akkodis'
        }

        BeforeEach {
            # Reset the parameters
            $references = @{}
            $variables = @{}
            $parameters = @{}

            Mock -CommandName Write-Host
            Mock -CommandName Write-Error
            Mock -CommandName Write-Verbose
            Mock -CommandName Write-Warning

        }

        It "Should use the custom execution method for Test" {

            $params.ConfigurationMode = 'Audit'
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\CustomExecutionMethod'

            #Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { return @{} }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith { return @{ InDesiredState = $true } }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' }
            Mock -CommandName Write-Verbose

            Invoke-DscPipelineRunner @params

            # The per-resource execution-method override is no longer announced via
            # Write-Verbose (Start-DscRunner now logs structured per-resource results via
            # Write-Information instead); the override taking effect is asserted behaviorally
            # here via the resulting Invoke-DscResource call pattern.
            Assert-MockCalled -CommandName Invoke-DscResource -Times 2 -ParameterFilter { $Method -eq 'Test' }
            Assert-MockCalled -CommandName Invoke-DscResource -Exactly 0 -ParameterFilter { $Method -eq 'Set' }

        }

        It "Should not use the custom execution method for None" {

            $params.ConfigurationMode = 'Enforce'
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\CustomExecutionMethod#2'

            #Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' } -MockWith { return @{} }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Test' } -MockWith { return @{ InDesiredState = $true } }
            Mock -CommandName Invoke-DscResource -ParameterFilter { $Method -eq 'Set' }
            Mock -CommandName Write-Verbose

            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            # 'None' means no per-resource override; the resource is evaluated under the
            # ConfigurationMode's own engine action (Enforce here) instead of being forced
            # through 'Test' only, same as any other resource without an override.
            Assert-MockCalled -CommandName Invoke-DscResource -Times 1 -ParameterFilter { $Method -eq 'Test' }

        }

    }

    Context "When running Invoke-DscPipelineRunner with -ContinueOnError" {

        BeforeAll {
            Import-Module 'DSC.PipelineRunner.Akkodis'
        }

        BeforeEach {
            $references = @{}
            $variables  = @{}
            $parameters = @{}

            Mock -CommandName Write-Host
            Mock -CommandName Write-Error
            Mock -CommandName Write-Verbose
            Mock -CommandName Write-Warning

            # Make AzDoProject's Test report not-in-desired-state so Set is triggered
            Mock -CommandName Invoke-DscResource -ParameterFilter {
                $Method -eq 'Test' -and $Name -eq 'AzDoProject'
            } -MockWith { return @{ InDesiredState = $false } }

            # Make AzDoProject's Set fail
            Mock -CommandName Invoke-DscResource -ParameterFilter {
                $Method -eq 'Set' -and $Name -eq 'AzDoProject'
            } -MockWith { throw "Mocked AzDoProject Set failure" }

        }

        AfterEach {
            $params.ConfigurationMode = 'Audit'
            $params.Remove('ContinueOnError')
        }

        It "Should stop all subsequent tasks when a Set fails and -ContinueOnError is NOT specified" {
            $params.ConfigurationMode = 'Enforce'
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\ContinueOnError'

            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # One row per resource. Project runs first and fails, so the other three are skipped.
            $report | Should -HaveCount 4
            $report | Where-Object { $_.Status -eq 'FAIL' } | Select-Object -ExpandProperty InstanceName | Should -Be 'Project'
            $report | Where-Object { $_.Status -eq 'SKIP' } | Should -HaveCount 3
            $report | Where-Object { $_.Status -eq 'OK' }   | Should -BeNullOrEmpty
        }

        It "Should skip only dependent resources and continue with independent resources when -ContinueOnError is specified" {
            $params.ConfigurationMode = 'Enforce'
            $params.ContinueOnError   = $true
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\ContinueOnError'

            { Invoke-DscPipelineRunner @params } | Should -Not -Throw

            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Project=FAIL, DependentOnProject=SKIP, IndependentResource and DependentOnIndependent=OK
            $report | Should -HaveCount 4
            $report | Where-Object { $_.Status -eq 'FAIL' } | Select-Object -ExpandProperty InstanceName | Should -Be 'Project'
            $report | Where-Object { $_.Status -eq 'SKIP' } | Select-Object -ExpandProperty InstanceName | Should -Be 'DependentOnProject'
            ($report | Where-Object { $_.Status -eq 'OK' }).InstanceName | Sort-Object | Should -Be @('DependentOnIndependent', 'IndependentResource')
        }

    }

}