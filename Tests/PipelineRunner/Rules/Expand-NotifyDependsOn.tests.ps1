
Describe "Expand-NotifyDependsOn" -Tag Unit, PipelineRunner, Rules, Custom {

    BeforeAll {

        # Load the function to test
        $customTaskFilePath = (Get-FunctionPath 'Expand-NotifyDependsOn.ps1').FullName

    }

    It "Returns the same (null) value when no resources are supplied" {
        $result = . $customTaskFilePath -PipelineResources $null

        $result | Should -BeNullOrEmpty
    }

    It "Returns the same empty array when an empty array of resources is supplied" {
        $result = . $customTaskFilePath -PipelineResources @()

        @($result).Count | Should -Be 0
    }

    It "Leaves resources without Notify untouched" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @() },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @() }
        )

        $result = . $customTaskFilePath -PipelineResources $resources

        @($result).Count | Should -Be 2
        $result[0].DependsOn | Should -BeNullOrEmpty
        $result[1].DependsOn | Should -BeNullOrEmpty
    }

    It "Adds the notifying resource to the target's DependsOn" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/Task2') },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @() }
        )

        $result = . $customTaskFilePath -PipelineResources $resources

        ($result | Where-Object Name -eq 'Task2').DependsOn | Should -Be @('Module/Resource/Task1')
    }

    It "Preserves the target's existing DependsOn entries when adding the implicit one" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/Task2') },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @('Module/Resource/Task0') }
        )

        $result = . $customTaskFilePath -PipelineResources $resources

        ($result | Where-Object Name -eq 'Task2').DependsOn | Should -Be @('Module/Resource/Task0', 'Module/Resource/Task1')
    }

    It "Supports notifying multiple targets" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/Task2', 'Module/Resource/Task3') },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @() },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task3'; DependsOn = @() }
        )

        $result = . $customTaskFilePath -PipelineResources $resources

        ($result | Where-Object Name -eq 'Task2').DependsOn | Should -Be @('Module/Resource/Task1')
        ($result | Where-Object Name -eq 'Task3').DependsOn | Should -Be @('Module/Resource/Task1')
    }

    It "Does not add a duplicate DependsOn entry when the target already depends on the notifier" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/Task2') },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @('Module/Resource/Task1') }
        )

        $result = . $customTaskFilePath -PipelineResources $resources

        @(($result | Where-Object Name -eq 'Task2').DependsOn).Count | Should -Be 1
    }

    It "Ignores blank/whitespace-only Notify entries" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('   ') },
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task2'; DependsOn = @() }
        )

        { . $customTaskFilePath -PipelineResources $resources } | Should -Not -Throw
    }

    It "Throws when a resource notifies itself" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/Task1') }
        )

        { . $customTaskFilePath -PipelineResources $resources } | Should -Throw "*cannot notify itself*"
    }

    It "Throws when a notify target is not present in the configuration" {
        $resources = @(
            [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1'; DependsOn = @(); Notify = @('Module/Resource/DoesNotExist') }
        )

        { . $customTaskFilePath -PipelineResources $resources } | Should -Throw "*not present in the configuration*"
    }

}
