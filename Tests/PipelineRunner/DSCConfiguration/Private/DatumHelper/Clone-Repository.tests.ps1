
Describe 'Clone-Repository Function Tests' -Tag Unit {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Clone-Repository.ps1').FullName
        $newTempDir = (Get-FunctionPath 'New-TemporaryDirectory.ps1').FullName
        $assertSecureGitUrlPath = (Get-FunctionPath 'Assert-SecureGitUrl.ps1').FullName

        . $preParseFilePath
        . $newTempDir
        . $assertSecureGitUrlPath

   

        Mock New-TemporaryDirectory { return (New-MockDirectoryPath) }
        # Clone-Repository checks $LASTEXITCODE after each git call; the mock must set it to 0
        # itself since a mocked call doesn't touch it, and a leftover nonzero value from an
        # earlier real git invocation elsewhere in the process would otherwise make this look
        # like a failed clone.
        Mock git { $global:LASTEXITCODE = 0 }

    }

    Context 'When called with valid parameters' {
        It 'Should clone the repository to the temporary directory' {
            # Arrange
            $DatumURLConfig = 'https://example.com/repo.git'

            # Act
            Clone-Repository -DatumURLConfig $DatumURLConfig

            # Assert: one call to clone, one to resolve HEAD's commit SHA for the audit log.
            Assert-MockCalled git -Exactly 2 -Scope It
        }
    }

    Context 'When called with invalid URL' {
        It 'Should handle the error when the Git URL is invalid' {
            # Arrange
            $DatumURLConfig = 'invalid-url'

            # Act & Assert
            { Clone-Repository -DatumURLConfig $DatumURLConfig } | Should -Throw
        }
    }
}
