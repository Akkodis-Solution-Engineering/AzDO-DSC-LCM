Describe "Invoke-EngineAction Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $dscMethodResultPath = (Get-FunctionPath '005.DscMethodResult.ps1').FullName
        $convertToDscMethodResultPath = (Get-FunctionPath 'ConvertTo-DscMethodResult.ps1').FullName
        $invokeActionPath = (Get-FunctionPath 'Invoke-Action.ps1').FullName
        $functionPath = (Get-FunctionPath 'Invoke-EngineAction.ps1').FullName

        . $dscMethodResultPath
        . $convertToDscMethodResultPath
        . $invokeActionPath
        . $functionPath

    }

    Context "When the engine returns a raw result" {

        BeforeEach {
            Mock Invoke-Action { return @{ InDesiredState = $true; Message = 'ok' } }
        }

        It "should build the engine context and dispatch to Invoke-Action with the Engine hook" {
            $property = @{ Ensure = 'Present' }
            Invoke-EngineAction -Method Test -ModuleName 'PSDscResources' -Name 'Service' -Property $property -Engine 'DscV2' | Out-Null

            Assert-MockCalled Invoke-Action -Exactly 1 -Scope It -ParameterFilter {
                $Hook -eq 'Engine' -and
                $Name -eq 'DscV2' -and
                $Context.Method -eq 'Test' -and
                $Context.ModuleName -eq 'PSDscResources' -and
                $Context.Name -eq 'Service' -and
                $Context.Property.Ensure -eq 'Present'
            }
        }

        It "should default the Engine to 'DscV2'" {
            Invoke-EngineAction -Method Get -ModuleName 'Mod' -Name 'Res' | Out-Null

            Assert-MockCalled Invoke-Action -Exactly 1 -Scope It -ParameterFilter {
                $Name -eq 'DscV2'
            }
        }

        It "should return a normalized DscMethodResult" {
            $result = Invoke-EngineAction -Method Test -ModuleName 'Mod' -Name 'Res'

            # NOTE: deliberately avoid a [DscMethodResult] type literal here - when this test
            # file runs alongside other files that also dot-source the class (e.g.
            # ConvertTo-DscMethodResult.tests.ps1), a type literal parsed during Pester's
            # discovery pass (before any class is defined) can fail to resolve at runtime.
            $result.GetType().Name | Should -Be 'DscMethodResult'
            $result.InDesiredState | Should -BeTrue
            $result.Message | Should -Be 'ok'
        }

        It "should pass an inline -EngineAction scriptblock through to Invoke-Action" {
            $sb = { param($Context) return @{ InDesiredState = $false } }
            Invoke-EngineAction -Method Test -ModuleName 'Mod' -Name 'Res' -EngineAction $sb | Out-Null

            Assert-MockCalled Invoke-Action -Exactly 1 -Scope It -ParameterFilter {
                $null -ne $ScriptBlock
            }
        }

        It "should thread the Session through the engine context" {
            $fakeSession = [pscustomobject]@{ Id = 'sess' }
            Invoke-EngineAction -Method Test -ModuleName 'Mod' -Name 'Res' -Session $fakeSession | Out-Null

            Assert-MockCalled Invoke-Action -Exactly 1 -Scope It -ParameterFilter {
                $Context.Session -eq $fakeSession
            }
        }

    }

    Context "When the engine returns nothing for a Test" {

        BeforeEach {
            Mock Invoke-Action { return $null }
        }

        It "should propagate the ConvertTo-DscMethodResult contract violation" {
            { Invoke-EngineAction -Method Test -ModuleName 'Mod' -Name 'Res' } | Should -Throw "*returned no result*"
        }

    }

}
