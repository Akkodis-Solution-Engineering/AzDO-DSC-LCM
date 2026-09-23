Describe "Test-DscExecutableAvailable Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $functionPath = (Get-FunctionPath 'Test-DscExecutableAvailable.ps1').FullName
        . $functionPath

    }

    It "should return true when Get-Command resolves the executable as an application" {
        Mock Get-Command { return [pscustomobject]@{ Name = 'dsc'; CommandType = 'Application' } }

        $result = Test-DscExecutableAvailable -Executable 'dsc'
        $result | Should -BeTrue
    }

    It "should return false when Get-Command does not resolve the executable" {
        Mock Get-Command { return $null }

        $result = Test-DscExecutableAvailable -Executable 'dsc'
        $result | Should -BeFalse
    }

    It "should default the Executable parameter to 'dsc'" {
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'dsc' }

        Test-DscExecutableAvailable | Out-Null

        Assert-MockCalled Get-Command -Exactly 1 -Scope It -ParameterFilter { $Name -eq 'dsc' -and $CommandType -eq 'Application' }
    }

    It "should probe for the specific Executable name supplied" {
        Mock Get-Command { return $null }

        Test-DscExecutableAvailable -Executable 'custom-dsc' | Out-Null

        Assert-MockCalled Get-Command -Exactly 1 -Scope It -ParameterFilter { $Name -eq 'custom-dsc' }
    }

}
