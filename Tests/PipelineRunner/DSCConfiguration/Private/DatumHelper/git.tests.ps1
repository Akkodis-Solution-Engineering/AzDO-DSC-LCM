
Describe 'git Function Tests' -Tag Unit {

    BeforeAll {

        # Load the functions to test
        # NOTE: Get-FunctionPath does a case-insensitive name match, and since Actions/Source/Git.ps1
        # was added alongside this file (both named 'git.ps1' case-insensitively), it now returns two
        # results. Disambiguate explicitly to the DatumHelper git wrapper under test.
        $preParseFilePath = (Get-FunctionPath 'git.ps1') | Where-Object { $_.FullName -like '*DatumHelper*' } | Select-Object -First 1 -ExpandProperty FullName
        . $preParseFilePath

        # git wraps a JITToken into a Basic-auth header via ConvertTo-BasicAuthCredential; that
        # is a module Private function normally already in scope when this file runs inside the
        # imported module, so it must be dot-sourced here too.
        . (Get-FunctionPath 'ConvertTo-BasicAuthCredential.ps1').FullName

        Mock Get-Command {
            
            return @{
                Name = 'git'
                CommandType = 'Application'
                Definition = New-MockFilePath 'git.exe'
            }
        }

    }

    Context 'When called with valid arguments' {
        It 'Should call git with the correct parameters' {
            # Arrange
            $global:JITToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("username:password"))
            $args = @('clone', 'https://example.com/repo.git')

            # Act
            git @args

            # Assert
            Assert-MockCalled Get-Command -Exactly 1 -Scope It
        }
    }

    Context 'When git command fails' {
        It 'Should catch and return the error' {
            # Arrange
            $global:JITToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("username:password"))
            $args = @('invalid-command')

            Mock Get-Command { throw "git command not found" }

            # Act
            $result = git @args

            # Assert
            $result | Should -Be "git command not found"
        }
    }
}
