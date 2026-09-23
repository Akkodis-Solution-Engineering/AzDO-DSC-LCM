Describe "Invoke-Action Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $functionPath = (Get-FunctionPath 'Invoke-Action.ps1').FullName
        . $functionPath

    }

    Context "When -ScriptBlock is supplied" {

        BeforeEach {
            Mock Get-Module { throw "Get-Module should not be called when -ScriptBlock is supplied." }
        }

        It "should invoke the scriptblock with the Context and return its result, taking precedence over -Name" {
            $result = Invoke-Action -Hook Connect -Name 'IgnoredName' -ScriptBlock { param($Context) return $Context.Value } -Context @{ Value = 'from-scriptblock' }

            $result | Should -Be 'from-scriptblock'
        }

        It "should pass an empty hashtable by default" {
            $result = Invoke-Action -Hook Source -ScriptBlock { param($Context) return $Context.Count }

            $result | Should -Be 0
        }

    }

    Context "When no -Name and no -ScriptBlock is supplied" {

        It "should throw" {
            { Invoke-Action -Hook Source } | Should -Throw "*No action name or -ScriptBlock supplied*"
        }

    }

    Context "When resolving a file-based action" {

        BeforeAll {
            $moduleBaseDir = Join-Path $TestDrive 'ModuleBase'
            $sourceActionsDir = Join-Path $moduleBaseDir 'Actions/Source'
            New-Item -Path $sourceActionsDir -ItemType Directory -Force | Out-Null

            $actionFile = Join-Path $sourceActionsDir 'TestAction.ps1'
            Set-Content -Path $actionFile -Value 'param([hashtable]$Context = @{}) return "Hello, $($Context.Name)"'
        }

        BeforeEach {
            Mock Get-Module { return [pscustomobject]@{ ModuleBase = $moduleBaseDir } }
        }

        It "should locate and invoke the action script under Actions/<Hook>/<Name>.ps1" {
            $result = Invoke-Action -Hook Source -Name 'TestAction' -Context @{ Name = 'World' }

            $result | Should -Be 'Hello, World'
        }

        It "should throw a clear error when the action file does not exist" {
            { Invoke-Action -Hook Source -Name 'DoesNotExist' -Context @{} } | Should -Throw "*was not found at*"
        }

        It "should throw when -Name is whitespace" {
            { Invoke-Action -Hook Source -Name '   ' } | Should -Throw "*No action name or -ScriptBlock supplied*"
        }

    }

}
