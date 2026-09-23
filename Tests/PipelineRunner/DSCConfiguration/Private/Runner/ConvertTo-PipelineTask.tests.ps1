
Describe "ConvertTo-PipelineTask Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {

        $ExecutionMethod  = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName
        $DSCBaseResource  = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource     = (Get-FunctionPath '002.DSC_Resource.ps1').FullName

        # DSC_Resource references the [ExecutionMethod] enum, which is normally already loaded
        # when the module is imported as a whole; dot-source it here too since this file loads
        # the classes individually.
        . $ExecutionMethod
        . $DSCBaseResource
        . $DSC_Resource

        . (Get-FunctionPath 'ConvertTo-PipelineTask.ps1').FullName
    }

    Context "projecting a fully-populated DSC_Resource" {

        BeforeAll {
            $ht = @{
                name                    = 'TestResource'
                type                    = 'Module\Type'
                properties              = @{ key = 'value' }
                condition               = 'SomeCondition'
                postCondition           = 'SomePostCondition'
                postExecutionScript     = 'SomePostScript'
                preExecutionScript      = 'SomePreScript'
                dependsOn               = @('Module\Type/Other')
                notify                  = @('Module\Type/Notified')
                target                  = @{ ComputerName = 'srv01' }
                resourceCredential      = @{ UserName = 'svc' }
                mergable                = $true
                executionMethodOverride = 'Test'
            }
            $resource = [DSC_Resource]::new($ht)

            $task = ConvertTo-PipelineTask -Resource $resource
        }

        It "returns a [pscustomobject]" {
            $task | Should -BeOfType [System.Management.Automation.PSCustomObject]
        }

        It "carries Name and Type across unchanged" {
            $task.Name | Should -Be 'TestResource'
            $task.Type | Should -Be 'Module\Type'
        }

        It "carries Properties across unchanged" {
            $task.Properties | Should -Be $resource.properties
        }

        It "projects DependsOn as a [string[]]" {
            , $task.DependsOn | Should -BeOfType [string[]]
            $task.DependsOn | Should -Be @('Module\Type/Other')
        }

        It "projects Notify as a [string[]]" {
            , $task.Notify | Should -BeOfType [string[]]
            $task.Notify | Should -Be @('Module\Type/Notified')
        }

        It "projects Condition from the resource's preCondition-aliased condition value" {
            $task.Condition | Should -Be 'SomeCondition'
        }

        It "projects PreCondition from the same back-compat alias" {
            $task.PreCondition | Should -Be 'SomeCondition'
        }

        It "projects PostCondition unchanged" {
            $task.PostCondition | Should -Be 'SomePostCondition'
        }

        It "projects PreExecutionScript and PostExecutionScript unchanged" {
            $task.PreExecutionScript  | Should -Be 'SomePreScript'
            $task.PostExecutionScript | Should -Be 'SomePostScript'
        }

        It "projects Target and ResourceCredential unchanged" {
            $task.Target.ComputerName | Should -Be 'srv01'
            $task.ResourceCredential.UserName | Should -Be 'svc'
        }

        It "projects ExecutionMethodOverride as a [string]" {
            $task.ExecutionMethodOverride | Should -Be 'Test'
            $task.ExecutionMethodOverride | Should -BeOfType [string]
        }

        It "projects Mergable unchanged" {
            $task.Mergable | Should -Be $true
        }

        It "exposes every property Start-DscRunner's engine loop reads" {
            $expectedProperties = @(
                'Name', 'Type', 'Properties', 'DependsOn', 'Notify', 'Condition', 'PreCondition',
                'PostCondition', 'PreExecutionScript', 'PostExecutionScript', 'Target',
                'ResourceCredential', 'ExecutionMethodOverride', 'Mergable'
            )

            foreach ($property in $expectedProperties) {
                $task.PSObject.Properties.Name | Should -Contain $property
            }
        }
    }

    Context "projecting a minimal DSC_Resource" {

        BeforeAll {
            $ht = @{
                name       = 'MinimalResource'
                type       = 'Module\Type'
                properties = @{}
            }
            $resource = [DSC_Resource]::new($ht)

            $task = ConvertTo-PipelineTask -Resource $resource
        }

        It "defaults DependsOn and Notify to empty [string[]] arrays" {
            , $task.DependsOn | Should -BeOfType [string[]]
            $task.DependsOn.Count | Should -Be 0

            , $task.Notify | Should -BeOfType [string[]]
            $task.Notify.Count | Should -Be 0
        }

        It "leaves unset condition/script/target fields `$null" {
            $task.Condition          | Should -BeNullOrEmpty
            $task.PostCondition      | Should -BeNullOrEmpty
            $task.PreExecutionScript | Should -BeNullOrEmpty
            $task.Target             | Should -BeNullOrEmpty
        }

        It "defaults ExecutionMethodOverride to 'None' and Mergable to `$false" {
            $task.ExecutionMethodOverride | Should -Be 'None'
            $task.Mergable | Should -Be $false
        }
    }

    Context "pipeline input" {

        It "accepts a DSC_Resource from the pipeline" {
            $ht = @{
                name       = 'PipelineResource'
                type       = 'Module\Type'
                properties = @{}
            }
            $resource = [DSC_Resource]::new($ht)

            $task = $resource | ConvertTo-PipelineTask

            $task.Name | Should -Be 'PipelineResource'
        }

        It "projects each resource in a multi-item pipeline independently" {
            $resources = @(
                [DSC_Resource]::new(@{ name = 'First';  type = 'Module\Type'; properties = @{} })
                [DSC_Resource]::new(@{ name = 'Second'; type = 'Module\Type'; properties = @{} })
            )

            $tasks = @($resources | ConvertTo-PipelineTask)

            $tasks.Count | Should -Be 2
            $tasks[0].Name | Should -Be 'First'
            $tasks[1].Name | Should -Be 'Second'
        }
    }
}
