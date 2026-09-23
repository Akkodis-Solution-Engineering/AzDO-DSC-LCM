Describe "ConvertTo-DscMethodResult Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $dscMethodResultPath = (Get-FunctionPath '005.DscMethodResult.ps1').FullName
        . $dscMethodResultPath

        $functionPath = (Get-FunctionPath 'ConvertTo-DscMethodResult.ps1').FullName
        . $functionPath

    }

    Context "When InputObject is null" {

        It "should throw for any method" {
            { ConvertTo-DscMethodResult -InputObject $null -Method 'Test' } | Should -Throw "*returned no result*"
        }

    }

    Context "When InputObject is already a DscMethodResult" {

        It "should return it unchanged" {
            # NOTE: deliberately avoid a [DscMethodResult] type literal in this test file - when
            # it runs alongside other files that also dot-source the class (e.g.
            # Invoke-EngineAction.tests.ps1), a type literal parsed during Pester's discovery
            # pass (before any class is defined) can fail to resolve at runtime. Build the
            # already-normalized instance through the function itself instead.
            $existing = ConvertTo-DscMethodResult -InputObject @{ InDesiredState = $true; RebootRequired = $true; Message = 'already normalized'; Raw = 'raw-value' } -Method 'Get'

            $result = ConvertTo-DscMethodResult -InputObject $existing -Method 'Get'

            $result | Should -Be $existing
        }

    }

    Context "When InputObject is a hashtable" {

        It "should coerce fields for a Test result that includes InDesiredState" {
            $raw = @{ InDesiredState = $false; RebootRequired = $true; Message = 'drift detected' }

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Test'

            $result.GetType().Name | Should -Be 'DscMethodResult'
            $result.InDesiredState | Should -BeFalse
            $result.RebootRequired | Should -BeTrue
            $result.Message | Should -Be 'drift detected'
            $result.Raw | Should -Be $raw
        }

        It "should throw when a Test result is missing InDesiredState" {
            $raw = @{ Message = 'no state signal' }

            { ConvertTo-DscMethodResult -InputObject $raw -Method 'Test' } | Should -Throw "*did not include an 'InDesiredState' value*"
        }

        It "should default InDesiredState to true for a Set result missing the field" {
            $raw = @{ Message = 'set applied' }

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Set'

            $result.InDesiredState | Should -BeTrue
        }

        It "should default InDesiredState to true for a Get result missing the field" {
            $raw = @{}

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Get'

            $result.InDesiredState | Should -BeTrue
        }

        It "should default Raw to the InputObject when no Raw field is supplied" {
            $raw = @{ InDesiredState = $true }

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Test'

            $result.Raw | Should -Be $raw
        }

        It "should use an explicit Raw field when supplied" {
            $raw = @{ InDesiredState = $true; Raw = 'explicit-raw' }

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Test'

            $result.Raw | Should -Be 'explicit-raw'
        }

    }

    Context "When InputObject is a pscustomobject" {

        It "should read fields via property access" {
            $raw = [pscustomobject]@{ InDesiredState = $true; RebootRequired = $false; Message = 'ok from object' }

            $result = ConvertTo-DscMethodResult -InputObject $raw -Method 'Test'

            $result.GetType().Name | Should -Be 'DscMethodResult'
            $result.InDesiredState | Should -BeTrue
            $result.Message | Should -Be 'ok from object'
        }

        It "should throw for a Test result pscustomobject missing InDesiredState" {
            $raw = [pscustomobject]@{ Message = 'missing state' }

            { ConvertTo-DscMethodResult -InputObject $raw -Method 'Test' } | Should -Throw "*did not include an 'InDesiredState' value*"
        }

    }

}
