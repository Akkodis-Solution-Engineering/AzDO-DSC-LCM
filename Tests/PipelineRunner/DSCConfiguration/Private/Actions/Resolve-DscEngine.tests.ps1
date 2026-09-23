Describe "Resolve-DscEngine Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $testDscExecutableAvailablePath = (Get-FunctionPath 'Test-DscExecutableAvailable.ps1').FullName
        . $testDscExecutableAvailablePath

        $functionPath = (Get-FunctionPath 'Resolve-DscEngine.ps1').FullName
        . $functionPath

    }

    Context "When an explicit Engine is supplied" {

        BeforeEach {
            Mock Test-DscExecutableAvailable { throw "Test-DscExecutableAvailable should not be probed for an explicit engine." }
        }

        It "should return the requested engine verbatim, regardless of Version" {
            $result = Resolve-DscEngine -Engine 'DscV2' -Version '3.0.0'
            $result | Should -Be 'DscV2'
        }

        It "should return an arbitrary non-Auto engine name unchanged" {
            $result = Resolve-DscEngine -Engine 'CustomEngine'
            $result | Should -Be 'CustomEngine'
        }

    }

    Context "When Engine is 'Auto' and a decisive Version hint is supplied" {

        It "should select DscV3 for a major version >= 3 when the executable is available" {
            Mock Test-DscExecutableAvailable { return $true }

            $result = Resolve-DscEngine -Engine 'Auto' -Version '3.1.0'
            $result | Should -Be 'DscV3'
        }

        It "should select DscV3 for a major version >= 3 even when the executable is not available, but warn" {
            Mock Test-DscExecutableAvailable { return $false }
            Mock Write-Warning { }

            $result = Resolve-DscEngine -Engine 'Auto' -Version '3.0.0'

            $result | Should -Be 'DscV3'
            Assert-MockCalled Write-Warning -Exactly 1 -Scope It
        }

        It "should select DscV2 for major version 2 without probing the executable" {
            Mock Test-DscExecutableAvailable { throw "should not be called for a decisive v2 hint" }

            $result = Resolve-DscEngine -Engine 'Auto' -Version '2.5.0'
            $result | Should -Be 'DscV2'
        }

    }

    Context "When Engine is 'Auto' and no decisive Version hint is supplied" {

        It "should prefer DscV3 when the executable is resolvable" {
            Mock Test-DscExecutableAvailable { return $true }

            $result = Resolve-DscEngine -Engine 'Auto'
            $result | Should -Be 'DscV3'
        }

        It "should fall back to DscV2 when the executable is not resolvable" {
            Mock Test-DscExecutableAvailable { return $false }

            $result = Resolve-DscEngine -Engine 'Auto'
            $result | Should -Be 'DscV2'
        }

        It "should treat a non-parseable Version as absent and fall back to executable probing" {
            Mock Test-DscExecutableAvailable { return $true }

            $result = Resolve-DscEngine -Engine 'Auto' -Version 'not-a-version'
            $result | Should -Be 'DscV3'
        }

        It "should treat an empty Version as absent" {
            Mock Test-DscExecutableAvailable { return $false }

            $result = Resolve-DscEngine -Engine 'Auto' -Version ''
            $result | Should -Be 'DscV2'
        }

    }

}
