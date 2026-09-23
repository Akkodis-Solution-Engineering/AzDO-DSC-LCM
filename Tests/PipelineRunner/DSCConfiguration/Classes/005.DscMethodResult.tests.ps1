
Describe "DscMethodResult Class Tests" -Tag Unit {

    BeforeAll {

        $DscMethodResult = (Get-FunctionPath '005.DscMethodResult.ps1').FullName

        . $DscMethodResult

    }

    Context "Construction" {

        It "Can be constructed with the default (parameterless) constructor" {
            { [DscMethodResult]::new() } | Should -Not -Throw
        }

        It "Defaults InDesiredState to false" {
            $result = [DscMethodResult]::new()
            $result.InDesiredState | Should -Be $false
        }

        It "Defaults RebootRequired to false" {
            $result = [DscMethodResult]::new()
            $result.RebootRequired | Should -Be $false
        }

        It "Defaults Message to null" {
            $result = [DscMethodResult]::new()
            $result.Message | Should -BeNullOrEmpty
        }

        It "Defaults Raw to null" {
            $result = [DscMethodResult]::new()
            $result.Raw | Should -BeNullOrEmpty
        }

    }

    Context "Property types" {

        BeforeAll {
            $result = [DscMethodResult]::new()
        }

        It "InDesiredState is a [bool]" {
            $result.InDesiredState | Should -BeOfType ([bool])
        }

        It "RebootRequired is a [bool]" {
            $result.RebootRequired | Should -BeOfType ([bool])
        }

        It "Coerces a truthy value assigned to InDesiredState to a boolean" {
            $result.InDesiredState = $true
            $result.InDesiredState | Should -Be $true
        }

        It "Accepts an arbitrary string for Message" {
            $result.Message = 'The resource is in the desired state.'
            $result.Message | Should -Be 'The resource is in the desired state.'
        }

        It "Accepts an arbitrary object for Raw, unmodified" {
            $raw = [PSCustomObject]@{ InDesiredState = $true; ExtraField = 'value' }
            $result.Raw = $raw
            $result.Raw | Should -Be $raw
            $result.Raw.ExtraField | Should -Be 'value'
        }

    }

    Context "Independent instances" {

        It "Does not share state between separate instances" {
            $resultA = [DscMethodResult]::new()
            $resultB = [DscMethodResult]::new()

            $resultA.InDesiredState = $true
            $resultA.Message = 'From A'

            $resultB.InDesiredState | Should -Be $false
            $resultB.Message | Should -BeNullOrEmpty
        }

    }

}
