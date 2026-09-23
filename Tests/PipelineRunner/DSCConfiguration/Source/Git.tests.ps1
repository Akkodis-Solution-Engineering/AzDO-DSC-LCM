Describe "Actions/Source/Git Action Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        # 'git.ps1' (the module's git wrapper) also exists under source/Private/DatumHelper/;
        # string comparisons in PowerShell are case-insensitive by default, so filter explicitly
        # to the Source action.
        $script:actionPath = (Get-FunctionPath 'Git.ps1' | Where-Object { $_.FullName -match '[\\/]Actions[\\/]Source[\\/]' }).FullName

        function Get-PipelineAuthToken { param($Token) }
        function Clone-Repository { param($DatumURLConfig, $Revision) }

    }

    Context "When no Url or Path is supplied in the context" {

        BeforeEach {
            Mock Get-PipelineAuthToken { return $null }
            Mock Clone-Repository { return '/tmp/cloned' }
        }

        It "should throw" {
            { & $script:actionPath -Context @{} } | Should -Throw "*No 'Url' supplied*"
        }

    }

    Context "When a Url is supplied" {

        BeforeEach {
            Mock Get-PipelineAuthToken { return $null }
            Mock Clone-Repository { return '/tmp/cloned-repo' }
        }

        It "should clone the repository and return the cloned directory" {
            $result = & $script:actionPath -Context @{ Url = 'https://example.com/repo.git' }

            $result | Should -Be '/tmp/cloned-repo'
            Assert-MockCalled Clone-Repository -Exactly 1 -Scope It -ParameterFilter {
                $DatumURLConfig -eq 'https://example.com/repo.git'
            }
        }

        It "should resolve the auth token via Get-PipelineAuthToken with the context Token" {
            & $script:actionPath -Context @{ Url = 'https://example.com/repo.git'; Token = 'my-pat' } | Out-Null

            Assert-MockCalled Get-PipelineAuthToken -Exactly 1 -Scope It -ParameterFilter {
                $Token -eq 'my-pat'
            }
        }

        It "should not pass a Revision to Clone-Repository when none is supplied" {
            & $script:actionPath -Context @{ Url = 'https://example.com/repo.git' } | Out-Null

            Assert-MockCalled Clone-Repository -Exactly 1 -Scope It -ParameterFilter {
                $null -eq $Revision -or $Revision -eq ''
            }
        }

        It "should pass the Revision through to Clone-Repository when supplied" {
            & $script:actionPath -Context @{ Url = 'https://example.com/repo.git'; Revision = 'v1.2.3' } | Out-Null

            Assert-MockCalled Clone-Repository -Exactly 1 -Scope It -ParameterFilter {
                $Revision -eq 'v1.2.3'
            }
        }

    }

    Context "When only a Path is supplied (fallback for Url)" {

        BeforeEach {
            Mock Get-PipelineAuthToken { return $null }
            Mock Clone-Repository { return '/tmp/cloned-from-path' }
        }

        It "should use Path as the clone Url" {
            $result = & $script:actionPath -Context @{ Path = 'https://example.com/from-path.git' }

            $result | Should -Be '/tmp/cloned-from-path'
            Assert-MockCalled Clone-Repository -Exactly 1 -Scope It -ParameterFilter {
                $DatumURLConfig -eq 'https://example.com/from-path.git'
            }
        }

    }

}
