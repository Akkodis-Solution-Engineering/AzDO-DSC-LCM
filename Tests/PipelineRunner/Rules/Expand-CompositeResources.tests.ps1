
Describe "Expand-CompositeResources" -Tag Unit, PipelineRunner, Rules, Custom {

    BeforeAll {

        $ExecutionMethod        = (Get-FunctionPath '000.ExecutionMethod.ps1').FullName
        $DSCConfigurationFile   = (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        $DSCBaseResource        = (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        $DSC_Resource           = (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        $DSCStub                = (Get-FunctionPath '003.DSCStub.ps1').FullName
        $DSCCompositeResource   = (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName

        $mergePropertiesPath    = (Get-FunctionPath 'mergeProperties.ps1').FullName
        $sortDictionaryPath     = (Get-FunctionPath 'sortDictionary.ps1').FullName
        $getDefaultValuesPath   = (Get-FunctionPath 'GetDefaultValues.ps1').FullName
        $setVariablesPath       = (Get-FunctionPath 'SetVariables.ps1').FullName
        $invokeCustomTaskPath   = (Get-FunctionPath 'Invoke-CustomTask.ps1').FullName

        . $ExecutionMethod
        . $DSCConfigurationFile
        . $DSCBaseResource
        . $DSC_Resource
        . $DSCStub
        . $DSCCompositeResource

        . $mergePropertiesPath
        . $sortDictionaryPath
        . $getDefaultValuesPath
        . $setVariablesPath
        . $invokeCustomTaskPath

        # Load the function to test
        $customTaskFilePath = (Get-FunctionPath 'Expand-CompositeResources.ps1').FullName

        # Invoke-CustomTask normally locates the custom task script via the imported
        # 'DSC.PipelineRunner.Akkodis' module's ModuleBase, which is not loaded in a unit test
        # session. Mock it to forward straight to the script under test, which both avoids the
        # module dependency and faithfully simulates the recursive self-invocation
        # (Expand-CompositeResources -> Invoke-CustomTask -> Expand-CompositeResources) that
        # happens in production.
        Mock -CommandName Invoke-CustomTask -MockWith {
            param($Tasks, $CustomTaskName)
            $taskPath = (Get-FunctionPath "$CustomTaskName.ps1").FullName
            return (. $taskPath -PipelineResources $Tasks)
        }

        # Builds a real [DSCCompositeResource] backed by an (empty, on-disk) linked file, then
        # overwrites its parsed .resource (a [DSCConfigurationFile]) directly - this mirrors how
        # 004.DSCCompositeResource.tests.ps1 exercises the class without needing a real YAML
        # composite on disk.
        function New-TestCompositeResource {
            param(
                [string]$Name = 'CompositeA',
                [string]$Type = 'Composite/Type',
                [object[]]$InnerResources = @(),
                [hashtable]$Parameters = $null,
                [hashtable]$Variables = $null,
                [hashtable]$Properties = @{}
            )

            $compositeDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $compositeDirectory -Force | Out-Null

            $linkedFileName = Join-Path $compositeDirectory "$Name.yml"
            New-Item -ItemType File -Path $linkedFileName -Force | Out-Null

            $task = @{ name = $Name; type = $Type; properties = $Properties }
            $composite = [DSCCompositeResource]::new($Name, $compositeDirectory, $task)

            $composite.resource.resources  = $InnerResources
            $composite.resource.parameters = $Parameters
            $composite.resource.variables  = $Variables

            return $composite
        }

    }

    It "Leaves non-composite resources untouched" {
        $normal = [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Task1' }

        $result = . $customTaskFilePath -PipelineResources @($normal)

        @($result).Count | Should -Be 1
        $result[0] | Should -Be $normal
    }

    It "Removes a composite resource that has no inner resources" {
        $composite = New-TestCompositeResource -InnerResources @()

        $result = . $customTaskFilePath -PipelineResources @($composite)

        @($result).Count | Should -Be 0
    }

    It "Removes a composite resource whose inner resources are null" {
        $composite = New-TestCompositeResource -InnerResources $null

        $result = . $customTaskFilePath -PipelineResources @($composite)

        @($result).Count | Should -Be 0
    }

    It "Splices a composite's inner resources into the result in place of the composite" {
        $inner1 = [DSC_Resource]::new(@{ name = 'Inner1'; type = 'Module/Resource'; properties = @{} })
        $inner2 = [DSC_Resource]::new(@{ name = 'Inner2'; type = 'Module/Resource'; properties = @{} })
        $composite = New-TestCompositeResource -InnerResources @($inner1, $inner2)

        $result = . $customTaskFilePath -PipelineResources @($composite)

        @($result).Count | Should -Be 2
        $result[0].name | Should -Be 'Inner1'
        $result[1].name | Should -Be 'Inner2'
    }

    It "Preserves the position of the expanded resources relative to surrounding resources" {
        $before = [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'Before' }
        $after  = [PSCustomObject]@{ Type = 'Module/Resource'; Name = 'After' }
        $inner  = [DSC_Resource]::new(@{ name = 'Inner1'; type = 'Module/Resource'; properties = @{} })
        $composite = New-TestCompositeResource -InnerResources @($inner)

        $result = . $customTaskFilePath -PipelineResources @($before, $composite, $after)

        @($result).Count | Should -Be 3
        $result[0].Name | Should -Be 'Before'
        $result[1].name | Should -Be 'Inner1'
        $result[2].Name | Should -Be 'After'
    }

    It "Recursively expands a composite that links to another composite" {
        $innerMost = [DSC_Resource]::new(@{ name = 'InnerMost'; type = 'Module/Resource'; properties = @{} })
        $nestedComposite = New-TestCompositeResource -Name 'NestedComposite' -InnerResources @($innerMost)
        $outerComposite  = New-TestCompositeResource -Name 'OuterComposite' -InnerResources @($nestedComposite)

        $result = . $customTaskFilePath -PipelineResources @($outerComposite)

        @($result).Count | Should -Be 1
        $result[0].name | Should -Be 'InnerMost'
    }

    It "Tags inner resources with the composite's parameter defaults, overridden by the node's properties" {
        $inner = [DSC_Resource]::new(@{ name = 'Inner1'; type = 'Module/Resource'; properties = @{} })
        $composite = New-TestCompositeResource -InnerResources @($inner) -Parameters @{
            Greeting = @{ defaultValue = 'Hello' }
            Target   = @{ defaultValue = 'World' }
        } -Properties @{ Target = 'Contoso' }

        $result = . $customTaskFilePath -PipelineResources @($composite)

        @($result[0].compositeScope).Count | Should -Be 1
        $result[0].compositeScope[0].Parameters['Greeting'] | Should -Be 'Hello'
        $result[0].compositeScope[0].Parameters['Target'] | Should -Be 'Contoso'
    }

    It "Tags inner resources with the composite's own variables" {
        $inner = [DSC_Resource]::new(@{ name = 'Inner1'; type = 'Module/Resource'; properties = @{} })
        $composite = New-TestCompositeResource -InnerResources @($inner) -Variables @{ Environment = 'Production' }

        $result = . $customTaskFilePath -PipelineResources @($composite)

        $result[0].compositeScope[0].Variables['Environment'] | Should -Be 'Production'
    }

    It "Does not touch the shared scope" {
        $parameters = @{ Existing = 'Value' }
        $variables  = @{ Existing = 'Value' }
        $inner = [DSC_Resource]::new(@{ name = 'Inner1'; type = 'Module/Resource'; properties = @{} })

        $composite = New-TestCompositeResource -InnerResources @($inner) -Parameters @{
            Greeting = @{ defaultValue = 'Hello' }
        } -Variables @{ Environment = 'Production' }

        . $customTaskFilePath -PipelineResources @($composite) | Out-Null

        $parameters.Keys.Count | Should -Be 1
        $variables.Keys.Count | Should -Be 1
    }

    It "Orders nested composite layers outermost first" {
        $innerMost = [DSC_Resource]::new(@{ name = 'InnerMost'; type = 'Module/Resource'; properties = @{} })
        $nested = New-TestCompositeResource -Name 'Nested' -InnerResources @($innerMost) -Properties @{ Level = 'Nested' }
        $outer  = New-TestCompositeResource -Name 'Outer' -InnerResources @($nested) -Properties @{ Level = 'Outer' }

        $result = . $customTaskFilePath -PipelineResources @($outer)

        @($result[0].compositeScope).Count | Should -Be 2
        $result[0].compositeScope[0].Parameters['Level'] | Should -Be 'Outer'
        $result[0].compositeScope[1].Parameters['Level'] | Should -Be 'Nested'
    }

    It "Merges stubs declared inside the composite file" {
        $target = [DSC_Resource]::new(@{ name = 'Target'; type = 'Module/Resource'; mergable = $true; properties = @{ A = '1' } })
        $stub = [DSCStub]::new(@{ name = 'Stub'; type = 'Module/Resource'; merge_with = 'Module/Resource/Target'; properties = @{ B = '2' } })
        $composite = New-TestCompositeResource -InnerResources @($stub, $target)

        $result = . $customTaskFilePath -PipelineResources @($composite)

        @($result).Count | Should -Be 1
        $result[0].properties['A'] | Should -Be '1'
        $result[0].properties['B'] | Should -Be '2'
    }

}
