Describe "Invoke-DscExecutable Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $functionPath = (Get-FunctionPath 'Invoke-DscExecutable.ps1').FullName
        . $functionPath

    }

    Context "When no Session is supplied (local execution)" {

        BeforeAll {
            function FakeDscExeSuccess {
                Write-Output "args:$($args -join ',')"
                $global:LASTEXITCODE = 0
            }

            function FakeDscExeFailure {
                Write-Output "boom"
                $global:LASTEXITCODE = 1
            }
        }

        It "should invoke the executable with the supplied arguments and capture success output/exit code" {
            $result = Invoke-DscExecutable -Executable 'FakeDscExeSuccess' -Arguments @('resource', 'list')

            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'args:resource,list'
        }

        It "should capture a non-zero exit code" {
            $result = Invoke-DscExecutable -Executable 'FakeDscExeFailure' -Arguments @('bad')

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'boom'
        }

        It "should default the Executable to 'dsc' when not supplied" {
            # Just verifies the default parameter value without invoking a real dsc.exe.
            (Get-Command Invoke-DscExecutable).Parameters['Executable'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Out-Null
            $ast = (Get-Command Invoke-DscExecutable).ScriptBlock.Ast
            $defaultValue = $ast.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Executable' }
            $defaultValue.DefaultValue.Value | Should -Be 'dsc'
        }

    }

    Context "When a Session is supplied (remote execution)" {

        BeforeEach {
            # Real Invoke-Command's -Session parameter is strictly typed to
            # [PSSession[]], which a Pester Mock preserves during parameter binding -
            # so a plain test double can't be passed through Mock's proxy. Shadowing
            # Invoke-Command with an ordinary (untyped) function achieves the same
            # interception without that constraint; PowerShell's command resolution
            # prefers a function over a cmdlet of the same name.
            $script:capturedSession = $null
            $script:capturedArgumentList = $null

            function Invoke-Command {
                param($Session, $ScriptBlock, $ArgumentList)
                $script:capturedSession = $Session
                $script:capturedArgumentList = $ArgumentList
                return @{ ExitCode = 0; Output = 'remote-output' }
            }
        }

        It "should dispatch the call through Invoke-Command against the supplied session" {
            $fakeSession = [pscustomobject]@{ Id = 'fake-session' }

            $result = Invoke-DscExecutable -Executable 'dsc' -Arguments @('resource', 'get') -Session $fakeSession

            $result.ExitCode | Should -Be 0
            $result.Output | Should -Be 'remote-output'

            $script:capturedSession | Should -Be $fakeSession
            $script:capturedArgumentList[0] | Should -Be 'dsc'
            $script:capturedArgumentList[1] | Should -Be @('resource', 'get')
        }

    }

}
