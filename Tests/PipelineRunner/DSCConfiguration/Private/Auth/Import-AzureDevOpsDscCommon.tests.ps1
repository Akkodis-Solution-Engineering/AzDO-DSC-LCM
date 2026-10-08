
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

        BeforeAll {
            # Stub so the mock binds on a host without PowerShellGet.
            function Install-Module { param($Name, $Scope, $Repository, [switch]$Force) }
        }

        BeforeEach {
            Mock Get-Module { } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDsc.Common' }
            Mock Write-Warning { }
        }

        It 'Should install AzureDevOpsDscNative for the current user and use its bundled copy' {
            $script:installed = $false
            Mock Install-Module { $script:installed = $true }
            Mock Get-Module {
                if ($script:installed) {
                    [pscustomobject]@{ Name = 'AzureDevOpsDscNative'; Version = [version]'1.2.0'; ModuleBase = Join-Path $TestDrive 'Native/1.2.0' }
                }
            } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDscNative' }

            Import-AzureDevOpsDscCommon

            Should -Invoke Install-Module -Exactly 1 -Scope It -ParameterFilter { $Name -eq 'AzureDevOpsDscNative' -and $Scope -eq 'CurrentUser' }
            ($env:PSModulePath -split [regex]::Escape($script:separator))[0] | Should -Be (Join-Path $TestDrive 'Native/1.2.0/Modules')
            Should -Invoke Import-Module -Exactly 1 -Scope It
        }

        It 'Should throw an actionable error when the install fails' {
            Mock Get-Module { } -ParameterFilter { $ListAvailable -and $Name -eq 'AzureDevOpsDscNative' }
            Mock Install-Module { throw 'no network' }

            { Import-AzureDevOpsDscCommon } | Should -Throw "*Install-Module AzureDevOpsDscNative -Scope CurrentUser*"
            Should -Invoke Import-Module -Exactly 0 -Scope It
        }
    }
}
