
Describe 'Import-AzureDevOpsDscCommon Function Tests' -Tag Unit, PipelineRunner, Auth {

    BeforeAll {

        # Load the function to test
        . (Get-FunctionPath 'Import-AzureDevOpsDscCommon.ps1').FullName

        $script:separator = [System.IO.Path]::PathSeparator
    }

    BeforeEach {
        $script:originalModulePath = $env:PSModulePath
        Mock Import-Module { } -ParameterFilter { $Name -eq 'AzureDevOpsDsc.Common' }
    }

    AfterEach {
        $env:PSModulePath = $script:originalModulePath
    }

    Context 'When a standalone AzureDevOpsDsc.Common is installed' {

        It 'Should import it without touching PSModulePath' {
            Mock Get-Module { [pscustomobject]@{ Name = 'AzureDevOpsDsc.Common' } } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDsc.Common' }

            Import-AzureDevOpsDscCommon

            $env:PSModulePath | Should -Be $script:originalModulePath
            Should -Invoke Import-Module -Exactly 1 -Scope It
        }
    }

    Context 'When only AzureDevOpsDscNative is installed' {

        BeforeEach {
            Mock Get-Module { } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDsc.Common' }
            Mock Get-Module {
                [pscustomobject]@{ Name = 'AzureDevOpsDscNative'; Version = [version]'1.1.0'; ModuleBase = Join-Path $TestDrive 'Native/1.1.0' }
                [pscustomobject]@{ Name = 'AzureDevOpsDscNative'; Version = [version]'1.2.0'; ModuleBase = Join-Path $TestDrive 'Native/1.2.0' }
            } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDscNative' }
        }

        It 'Should put the newest copy''s bundled Modules folder first on PSModulePath' {
            Import-AzureDevOpsDscCommon

            ($env:PSModulePath -split [regex]::Escape($script:separator))[0] | Should -Be (Join-Path $TestDrive 'Native/1.2.0/Modules')
            Should -Invoke Import-Module -Exactly 1 -Scope It
        }

        It 'Should not add the folder twice' {
            Import-AzureDevOpsDscCommon
            Import-AzureDevOpsDscCommon

            @($env:PSModulePath -split [regex]::Escape($script:separator) | Where-Object { $_ -eq (Join-Path $TestDrive 'Native/1.2.0/Modules') }).Count | Should -Be 1
        }
    }

    Context 'When neither module is installed' {

        It 'Should throw an actionable error' {
            Mock Get-Module { } -ParameterFilter { $ListAvailable }
            Mock Import-Module { throw 'module not found' } -ParameterFilter { $Name -eq 'AzureDevOpsDsc.Common' }

            { Import-AzureDevOpsDscCommon } | Should -Throw "*Install-Module AzureDevOpsDscNative*"
        }
    }
}
