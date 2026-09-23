
Describe 'New-TemporaryDirectory Function Tests' -Tag Unit {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'New-TemporaryDirectory.ps1').FullName
        . $preParseFilePath

        # New-TemporaryDirectory now resolves a cache root, locks down the new directory's
        # permissions, and registers it for later cleanup - all module Private functions
        # normally already in scope when this file runs inside the imported module.
        . (Get-FunctionPath 'Resolve-CacheDirectory.ps1').FullName
        . (Get-FunctionPath 'Set-PrivateDirectoryPermission.ps1').FullName
        . (Get-FunctionPath 'Register-RunnerTemporaryDirectory.ps1').FullName

        Mock -CommandName New-Item -MockWith {
            param($ItemType, $Path)
            $path = New-MockDirectoryPath
            return @{
                PSPath = "Microsoft.PowerShell.Core\FileSystem::$(New-MockDirectoryPath)"
                PSParentPath = "Microsoft.PowerShell.Core\FileSystem::$(New-MockDirectoryPath)"
                PSChildName = "SomeRandomDir"
                PSDrive = @{ Name = "C" }
                PSProvider = @{ Name = "FileSystem" }
                PSIsContainer = $true
                BaseName = "SomeRandomDir"
                Mode = "d----"
                Name = "SomeRandomDir"
                FullName = "$path\SomeRandomDir"
                Parent = $path
            }
        }

    }

    Context 'When creating a new temporary directory' {
        It 'Should create a directory in the temp path' {
            # Arrange
            $tempPath = [System.IO.Path]::GetTempPath()

            # Act
            $result = New-TemporaryDirectory

            # Assert
            $result | Should -Not -BeNullOrEmpty
            Assert-MockCalled New-Item -Exactly 1 -Scope It
        }
    }

}
