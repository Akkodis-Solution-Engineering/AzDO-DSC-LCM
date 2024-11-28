
BeforeDiscovery {
    # Perform the latest build. This will ensure that the latest version of the module is loaded.
    . .\Build.ps1 -Tasks Build
}


Describe "Invoke-AZDoLCM Intergration Tests" -Tag Intergration, Invoke-AZDoLCM {

    BeforeAll {

        # Load the module into memory
        $modulePath = Get-ModulePath

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
            Mode = 'test'
            ConfigurationSourcePath = $null
        }

    }

    Context "When running Invoke-AZDoLCM with a valid configuration" {

        It "Should not throw any errors when using 'StandardResources' test case" {
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'
            { Invoke-AZDoLCM @params } | Should -Not -Throw
        }

        It "Should not throw any errors when using 'StubResources' test case" {
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StubResources'
            { Invoke-AZDoLCM @params } | Should -Not -Throw
        }

        It "Should not throw any resource errors when 'StandardResources' test case" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StandardResources'
            $temp = Invoke-AzDOLCM @params
            { Invoke-AZDoLCM @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Result -eq 'SKIPPED' } | Should -BeNullOrEmpty
            $report | Where-Object { $_.Result -eq 'FAIL' } | Should -BeNullOrEmpty
        }

        It "Should not throw any resource errors when using 'StubResources' test case" {
            $params.ReportPath = (Join-Path $TestDrive -ChildPath 'Reports')
            $params.ConfigurationSourcePath = Join-Path $TestDrive -ChildPath 'TestCases\StubResources'
            { Invoke-AZDoLCM @params } | Should -Not -Throw

            # Load the reports
            $reports = Get-ChildItem -Path $params.ReportPath -Recurse -File
            $report = Import-CSV -Path $reports[0].FullName

            # Ensure that the report contains the correct number of resources
            $report | Should -HaveCount 4
            # Ensure that no result was skipped or failed
            $report | Where-Object { $_.Result -eq 'SKIPPED' } | Should -BeNullOrEmpty
            $report | Where-Object { $_.Result -eq 'FAIL' } | Should -BeNullOrEmpty            
        }

    }
}