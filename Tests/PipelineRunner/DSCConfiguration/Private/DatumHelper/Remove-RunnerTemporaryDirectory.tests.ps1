
Describe 'Remove-RunnerTemporaryDirectory Function Tests' -Tag Unit, PipelineRunner, DatumHelper {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Remove-RunnerTemporaryDirectory.ps1').FullName
        . $preParseFilePath

        # Remove-RunnerTemporaryDirectory only removes a path the registry recognises as
        # runner-created; Register-/Unregister-/Test-RunnerTemporaryDirectory are module
        # Private functions normally already in scope when this file runs inside the
        # imported module.
        . (Get-FunctionPath 'Register-RunnerTemporaryDirectory.ps1').FullName

        function New-TestDirectory {
            $path = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
            $null = New-Item -ItemType Directory -Path $path
            return $path
        }
    }

    BeforeEach {
        $script:RunnerTemporaryDirectoryRegistry = $null
    }

    Context 'Removal' {

        It 'Should delete a directory the runner created' {
            $path = New-TestDirectory
            Set-Content -LiteralPath (Join-Path $path 'file.txt') -Value 'content'
            Register-RunnerTemporaryDirectory -Path $path

            Remove-RunnerTemporaryDirectory -Path $path

            Test-Path -LiteralPath $path | Should -BeFalse
        }

        It 'Should never delete a caller-owned directory' {
            # The safety property that makes it valid to call this unconditionally from a
            # finally block: -ConfigurationSourcePath may be the user's working copy (#32).
            $path = New-TestDirectory

            Remove-RunnerTemporaryDirectory -Path $path

            Test-Path -LiteralPath $path | Should -BeTrue
        }

        It 'Should forget the directory after deleting it' {
            $path = New-TestDirectory
            Register-RunnerTemporaryDirectory -Path $path

            Remove-RunnerTemporaryDirectory -Path $path

            Test-RunnerTemporaryDirectory -Path $path | Should -BeFalse
        }

        It 'Should unregister a registered directory that is already gone' {
            $path = New-TestDirectory
            Register-RunnerTemporaryDirectory -Path $path
            Remove-Item -LiteralPath $path -Recurse -Force

            { Remove-RunnerTemporaryDirectory -Path $path } | Should -Not -Throw
            Test-RunnerTemporaryDirectory -Path $path | Should -BeFalse
        }

        It 'Should tolerate a null path' {
            { Remove-RunnerTemporaryDirectory -Path $null } | Should -Not -Throw
        }

        It 'Should tolerate an empty path' {
            { Remove-RunnerTemporaryDirectory -Path '' } | Should -Not -Throw
        }

        It 'Should warn rather than throw when removal fails' {
            $path = New-TestDirectory
            Register-RunnerTemporaryDirectory -Path $path
            Mock Remove-Item { throw 'in use' }

            { Remove-RunnerTemporaryDirectory -Path $path -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should still be registered after a failed removal' {
            $path = New-TestDirectory
            Register-RunnerTemporaryDirectory -Path $path
            Mock Remove-Item { throw 'in use' }

            Remove-RunnerTemporaryDirectory -Path $path -WarningAction SilentlyContinue

            Test-RunnerTemporaryDirectory -Path $path | Should -BeTrue
        }
    }

    Context 'ShouldProcess support' {

        It 'Should not remove the directory when -WhatIf is supplied' {
            $path = New-TestDirectory
            Register-RunnerTemporaryDirectory -Path $path

            Remove-RunnerTemporaryDirectory -Path $path -WhatIf

            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }
}
