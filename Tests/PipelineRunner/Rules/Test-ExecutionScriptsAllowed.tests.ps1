
Describe "Test-ExecutionScriptsAllowed" -Tag Unit, PipelineRunner, Rules, PreParse {

    BeforeAll {

        # Load the function to test
        $preParseFilePath = (Get-FunctionPath 'Test-ExecutionScriptsAllowed.ps1').FullName

    }

    Context "When AllowExecutionScripts is not enabled" {

        It "Does not throw when no resource carries an execution script" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = $null; postExecutionScript = $null }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{} } | Should -Not -Throw
        }

        It "Throws when a resource carries a preExecutionScript" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = 'Write-Host 1'; postExecutionScript = $null }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{} } | Should -Throw "*AllowExecutionScripts*"
        }

        It "Throws when a resource carries a postExecutionScript" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = $null; postExecutionScript = 'Write-Host 1' }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{} } | Should -Throw "*AllowExecutionScripts*"
        }

        It "Names every offending resource in a single thrown error" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = 'Write-Host 1'; postExecutionScript = $null }
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task2'; preExecutionScript = $null; postExecutionScript = 'Write-Host 2' }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{} } | Should -Throw "*[Module/Resource/Task1]*[Module/Resource/Task2]*"
        }

        It "Defaults to disabled when Settings is not supplied" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = 'Write-Host 1'; postExecutionScript = $null }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings $null } | Should -Throw "*AllowExecutionScripts*"
        }

        It "Defaults to disabled when Settings does not contain the AllowExecutionScripts key" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = 'Write-Host 1'; postExecutionScript = $null }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{ SomeOtherSetting = $true } } | Should -Throw "*AllowExecutionScripts*"
        }

    }

    Context "When AllowExecutionScripts is enabled" {

        It "Does not throw even when resources carry execution scripts" {
            $resources = @(
                [PSCustomObject]@{ type = 'Module/Resource'; name = 'Task1'; preExecutionScript = 'Write-Host 1'; postExecutionScript = 'Write-Host 2' }
            )

            { . $preParseFilePath -PipelineResources $resources -Settings @{ AllowExecutionScripts = $true } } | Should -Not -Throw
        }

    }

}
