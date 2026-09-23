
Describe 'Set-PrivateDirectoryPermission Function Tests' -Tag Unit, PipelineRunner, DatumHelper {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Set-PrivateDirectoryPermission.ps1').FullName
        . $preParseFilePath

    }

    Context 'On a Unix host' -Skip:($IsWindows -or $env:OS -eq 'Windows_NT') {

        It 'Should restrict the directory to mode 0700' {
            # Arrange
            $directory = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $directory

            # Act
            Set-PrivateDirectoryPermission -Path $directory

            # Assert
            $mode = [System.IO.File]::GetUnixFileMode($directory)
            $mode | Should -Be ([System.IO.UnixFileMode]::UserRead -bor
                                [System.IO.UnixFileMode]::UserWrite -bor
                                [System.IO.UnixFileMode]::UserExecute)
        }

        It 'Should leave the directory usable by the current process' {
            # Arrange
            $directory = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $directory

            # Act
            Set-PrivateDirectoryPermission -Path $directory
            $file = Join-Path $directory 'probe.txt'
            Set-Content -LiteralPath $file -Value 'probe'

            # Assert
            Get-Content -LiteralPath $file | Should -Be 'probe'
        }
    }

    Context 'On a Windows host' -Skip:(-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {

        It 'Should grant the current identity full control and break inheritance' {
            # Arrange
            $directory = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $directory

            # Act
            Set-PrivateDirectoryPermission -Path $directory

            # Assert
            $acl = Get-Acl -LiteralPath $directory
            $acl.AreAccessRulesProtected | Should -BeTrue

            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = $acl.Access | Where-Object { $_.IdentityReference -eq $identity }
            $rule | Should -Not -BeNullOrEmpty
            $rule.FileSystemRights.ToString() | Should -Match 'FullControl'
        }
    }

    Context 'When the directory cannot be secured' {

        It 'Should warn rather than throw' {
            $missing = Join-Path $TestDrive 'no-such-directory'

            { Set-PrivateDirectoryPermission -Path $missing -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'ShouldProcess support' {

        It 'Should not modify the directory when -WhatIf is supplied' {
            $directory = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $directory

            { Set-PrivateDirectoryPermission -Path $directory -WhatIf } | Should -Not -Throw
        }
    }
}
