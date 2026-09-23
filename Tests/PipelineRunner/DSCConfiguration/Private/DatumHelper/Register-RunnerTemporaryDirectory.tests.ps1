
Describe 'Register-RunnerTemporaryDirectory Function Tests' -Tag Unit, PipelineRunner, DatumHelper {

    BeforeAll {

        # Load the functions to test. Register-RunnerTemporaryDirectory, Test-RunnerTemporaryDirectory,
        # Unregister-RunnerTemporaryDirectory, Get-RunnerTemporaryDirectoryRegistry and
        # ConvertTo-RunnerTemporaryDirectoryKey all live in this one source file.
        $preParseFilePath = (Get-FunctionPath 'Register-RunnerTemporaryDirectory.ps1').FullName
        . $preParseFilePath

    }

    BeforeEach {
        # The registry is a module-scoped set; reset it so each test starts from empty
        # regardless of test execution order.
        $script:RunnerTemporaryDirectoryRegistry = $null
    }

    Context 'Registering a directory' {

        It 'Should report a registered directory as runner-created' {
            $path = '/tmp/example-dir'
            Register-RunnerTemporaryDirectory -Path $path

            Test-RunnerTemporaryDirectory -Path $path | Should -BeTrue
        }

        It 'Should be case-insensitive when comparing paths' {
            $path = '/tmp/Example-Dir'
            Register-RunnerTemporaryDirectory -Path $path

            Test-RunnerTemporaryDirectory -Path '/tmp/example-dir' | Should -BeTrue
        }

        It 'Should ignore a trailing directory separator' {
            $path = '/tmp/example-dir'
            Register-RunnerTemporaryDirectory -Path $path

            Test-RunnerTemporaryDirectory -Path ($path + [System.IO.Path]::DirectorySeparatorChar) | Should -BeTrue
        }

        It 'Should tolerate registering the same path twice' {
            $path = '/tmp/example-dir'
            Register-RunnerTemporaryDirectory -Path $path

            { Register-RunnerTemporaryDirectory -Path $path } | Should -Not -Throw
            Test-RunnerTemporaryDirectory -Path $path | Should -BeTrue
        }
    }

    Context 'Testing an unregistered directory' {

        It 'Should report an unregistered directory as caller-owned' {
            Test-RunnerTemporaryDirectory -Path '/tmp/never-registered' | Should -BeFalse
        }

        It 'Should report an empty path as caller-owned' {
            Test-RunnerTemporaryDirectory -Path '' | Should -BeFalse
        }
    }

    Context 'Unregistering a directory' {

        It 'Should forget a directory once unregistered' {
            $path = '/tmp/example-dir'
            Register-RunnerTemporaryDirectory -Path $path
            Unregister-RunnerTemporaryDirectory -Path $path

            Test-RunnerTemporaryDirectory -Path $path | Should -BeFalse
        }

        It 'Should tolerate unregistering a path that was never registered' {
            { Unregister-RunnerTemporaryDirectory -Path '/tmp/never-registered' } | Should -Not -Throw
        }
    }

    Context 'Get-RunnerTemporaryDirectoryRegistry' {

        It 'Should return a HashSet the first time it is called' {
            $registry = Get-RunnerTemporaryDirectoryRegistry

            # Piping $registry to Should would enumerate it (it may be an empty HashSet,
            # which enumerates to nothing), so assert on it directly instead.
            Should -ActualValue $registry -BeOfType ([System.Collections.Generic.HashSet[string]])
        }

        It 'Should return the same registry instance across calls' {
            $first = Get-RunnerTemporaryDirectoryRegistry
            $null = $first.Add('/tmp/marker')

            $second = Get-RunnerTemporaryDirectoryRegistry

            $second.Contains('/tmp/marker') | Should -BeTrue
        }
    }

    Context 'ConvertTo-RunnerTemporaryDirectoryKey' {

        It 'Should trim a trailing directory separator' {
            ConvertTo-RunnerTemporaryDirectoryKey -Path '/tmp/example/' | Should -Be '/tmp/example'
        }

        It 'Should leave a path with no trailing separator unchanged' {
            ConvertTo-RunnerTemporaryDirectoryKey -Path '/tmp/example' | Should -Be '/tmp/example'
        }
    }
}
