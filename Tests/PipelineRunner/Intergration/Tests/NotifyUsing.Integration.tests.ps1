Describe "notify/using() gated reads through a real runner pass" -Tag Integration, HostedIntegration {

    AfterAll {
        Restore-ProcessEnvironment -Snapshot $script:ProcessEnvironment
    }

    # The unit suites cover the two halves of this feature in isolation: using.tests.ps1 drives
    # invoke-using against a hand-built $script:notifyDeclarations / $script:resourceOutputs pair,
    # Expand-NotifyDependsOn.tests.ps1 drives the ordering rule, and Start-DscRunner.tests.ps1
    # asserts the forced-refresh semantics with ConvertFrom-Json and Invoke-DscResource mocked.
    #
    # None of them proves the pieces line up. This suite runs the genuine Start-DscRunner loop
    # over a real configuration file on disk and asserts that a value produced by one resource's
    # Get() actually arrives in another resource's properties via using(), that the notify gate
    # rejects an undeclared read, and that the same gate holds when the declaration exists but
    # names someone else. Those three facts depend on the real collaboration between:
    #
    #   * the declaration map built from each resource's `notify` list   (Start-DscRunner.ps1)
    #   * Expand-NotifyDependsOn turning `notify` into ordering          (Pipeline Rules/Custom)
    #   * Sort-DependsOn's topological order                            (Pipeline Rules/Custom)
    #   * $script:currentResourceKey set before property expansion      (Start-DscRunner.ps1)
    #   * Expand-HashTable / ExpandString invoking the `using` alias
    #   * $script:resourceOutputs written from the real Get() output    (Start-DscRunner.ps1)
    #
    # Only the rule LOADERS are substituted (Invoke-CustomTask's production path resolves
    # Windows-style "ModuleBase\Pipeline Rules\..." paths and calls Get-DscResource against
    # resources that are not installed in CI); the stub dispatches to the REAL rule scripts
    # under "Pipeline Rules/Custom", so ordering and notify expansion are genuinely exercised.
    # The two new pipeline stages this repo added ahead of Dsc.PipelineRunner's own
    # (Merge-StubResources, Expand-CompositeResources) fall through the stub's default arm,
    # which passes the tasks through unchanged - exactly what a configuration with no stub or
    # composite resources needs. The class-based parsing chain
    # (DSCConfigurationFile/DSC_Resource/.../ConvertTo-PipelineTask) is this repo's own addition
    # on top of Dsc.PipelineRunner's engine-agnostic loop and is dot-sourced for real below, so
    # [DSCConfigurationFile]::New() inside Start-DscRunner genuinely parses the JSON fixtures
    # this suite writes to TestDrive. The engine is an inline -EngineAction, so this suite is
    # hermetic and cross-platform - no Invoke-DscResource, no dsc.exe.

    BeforeAll {
        # Suites share one process; see Save-ProcessEnvironment for why this matters.
        $script:ProcessEnvironment = Save-ProcessEnvironment

        # This repo's class-based configuration parsing chain (MERGE-PLAN.md §4-5), which
        # Start-DscRunner's [DSCConfigurationFile]::New() call and ConvertTo-PipelineTask depend
        # on. Dot-sourced in dependency order: 004.DSCCompositeResource.ps1 declares a
        # [DSCConfigurationFile]-typed member, so 000.DSCConfigurationFile.ps1 must already be
        # defined by the time 004 is parsed; 002.DSC_Resource.ps1 declares an [ExecutionMethod]
        # member, so the enum precedes it.
        . (Get-FunctionPath '000.ExecutionMethod.ps1').FullName
        . (Get-FunctionPath '000.DSCConfigurationFile.ps1').FullName
        . (Get-FunctionPath '001.DSCBaseResource.ps1').FullName
        . (Get-FunctionPath '002.DSC_Resource.ps1').FullName
        . (Get-FunctionPath '003.DSCStub.ps1').FullName
        . (Get-FunctionPath '004.DSCCompositeResource.ps1').FullName
        . (Get-FunctionPath '005.DscMethodResult.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-Resource.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-PipelineTask.ps1').FullName

        . (Get-FunctionPath 'Invoke-Action.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-DscMethodResult.ps1').FullName
        . (Get-FunctionPath 'Invoke-EngineAction.ps1').FullName

        . (Get-FunctionPath 'Start-DscRunner.ps1').FullName
        . (Get-FunctionPath 'GetDefaultValues.ps1').FullName
        . (Get-FunctionPath 'SetVariables.ps1').FullName
        . (Get-FunctionPath 'Set-CompositeScope.ps1').FullName
        . (Get-FunctionPath 'Test-RunnerReservedVariableName.ps1').FullName
        . (Get-FunctionPath 'ConvertTo-CaseInsensitiveHashtable.ps1').FullName
        . (Get-FunctionPath 'Expand-HashTable.ps1').FullName
        . (Get-FunctionPath 'Expand-StringInArray.ps1').FullName
        . (Get-FunctionPath 'Expand-Parameters.ps1').FullName
        . (Get-FunctionPath 'Expand-ParameterInArray.ps1').FullName
        . (Get-FunctionPath 'Resolve-PipelineParameter.ps1').FullName
        . (Get-FunctionPath 'Assert-SafeConditionExpression.ps1').FullName
        . (Get-FunctionPath 'Stop-TaskProcessing.ps1').FullName

        # The accessor under test. Dot-sourcing it defines the 'using' alias in this scope, which
        # is what ExpandString resolves when it expands a property containing "$(using '...')".
        . (Get-FunctionPath 'using.ps1').FullName
        . (Get-FunctionPath 'reference.ps1').FullName

        . (Get-FunctionPath 'Invoke-CustomTask.ps1').FullName
        . (Get-FunctionPath 'Invoke-PreParseRules.ps1').FullName
        . (Get-FunctionPath 'Invoke-FormatTasks.ps1').FullName

        $references = @{}
        $variables  = @{}
        $parameters = @{}

        # A directory that need not exist: none of this suite's fixtures use `type:
        # composite/...`, so [DSCConfigurationFile] never resolves a path under it, but
        # Start-DscRunner's -DSCCompositeResourcePath parameter is mandatory.
        $script:CompositeResourcePath = Join-Path $TestDrive 'Composite'

        $script:SortDependsOnPath   = (Get-FunctionPath 'Sort-DependsOn.ps1').FullName
        $script:ExpandNotifyPath    = (Get-FunctionPath 'Expand-NotifyDependsOn.ps1').FullName

        Mock -CommandName Get-Module -MockWith { return @{ moduleBase = $Global:RepositoryRoot } }
        Mock -CommandName Write-Host
        Mock -CommandName Write-Information

        # Runs the REAL rule scripts, so notify-driven ordering and the topological sort are both
        # genuinely exercised rather than stubbed away. Merge-StubResources and
        # Expand-CompositeResources (this repo's own pipeline stages) fall through to the default
        # arm, which is the correct behavior for fixtures with no stub or composite resources.
        Mock -CommandName Invoke-CustomTask -MockWith {
            param(
                [Parameter(Mandatory = $true)] [Object[]]$Tasks,
                [Parameter(Mandatory = $true)] [String]$CustomTaskName
            )
            switch ($CustomTaskName) {
                'Expand-NotifyDependsOn' { return (& $script:ExpandNotifyPath -PipelineResources $Tasks) }
                'Sort-DependsOn'         { return (& $script:SortDependsOnPath -PipelineResources $Tasks) }
                default                  { return $Tasks }
            }
        }

        Mock -CommandName Invoke-PreParseRules -MockWith {
            param([Parameter(Mandatory = $true)] [Object[]]$Tasks, [hashtable]$Settings)
        }

        Mock -CommandName Invoke-FormatTasks -MockWith {
            param([Parameter(Mandatory = $true)] [Object[]]$Tasks)
            return $Tasks
        }

        # An engine that answers Get() with a per-resource payload and records the properties it
        # was handed, so a test can assert what using() actually resolved to. Every resource is
        # reported in the desired state; this suite is about data flow, not drift.
        function New-UsingEngine {
            param(
                [System.Collections.Generic.List[object]]$Calls,
                [hashtable]$GetOutputs = @{}
            )

            return {
                param($Context)
                $Calls.Add([pscustomobject]@{
                    Method   = $Context.Method
                    Name     = $Context.Name
                    Property = $Context.Property
                })
                $result = @{ InDesiredState = $true; Message = "stub-$($Context.Method)" }
                if ($Context.Method -eq 'Get' -and $GetOutputs.ContainsKey($Context.Name)) {
                    $result.Raw = $GetOutputs[$Context.Name]
                }
                return $result
            }.GetNewClosure()
        }

        function New-ConfigFile {
            param([string]$Name, [string]$Json)
            $path = Join-Path $TestDrive $Name
            Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
            return $path
        }
    }

    BeforeEach {
        $script:StopTaskProcessing = $false
    }

    It "carries a value from the notifying resource's Get() output into the notified resource's properties" {

        # Source notifies Consumer, so Consumer is allowed to read Source's Get() output. The
        # notify declaration also guarantees Source runs first, which is what makes the read
        # meaningful: $script:resourceOutputs must already hold Source's payload by the time
        # Consumer's properties are expanded.
        $json = @'
{
  "parameters": {},
  "variables": {},
  "resources": [
    { "type": "Module/Consumer", "name": "Consumer", "properties": { "projectId": "$((using 'Module/Source/Source').Id)" } },
    { "type": "Module/Source", "name": "Source", "properties": {}, "notify": [ "Module/Consumer/Consumer" ] }
  ]
}
'@
        $config = New-ConfigFile -Name 'using-happy-path.json' -Json $json
        $calls  = [System.Collections.Generic.List[object]]::new()
        $engine = New-UsingEngine -Calls $calls -GetOutputs @{ Source = [pscustomobject]@{ Id = 'proj-4711' } }

        $result = Start-DscRunner -FilePath $config -ConfigurationMode 'ApplyOnly' -DSCCompositeResourcePath $script:CompositeResourcePath -EngineAction $engine

        $result.Status    | Should -Be 'Completed'
        $result.FailCount | Should -Be 0

        # Ordering: Source was evaluated before Consumer even though Consumer is listed first,
        # because Expand-NotifyDependsOn turned the notify into a dependsOn for Sort-DependsOn.
        $testOrder = @($calls | Where-Object { $_.Method -eq 'Test' } | ForEach-Object { $_.Name })
        $testOrder | Should -Be @('Source', 'Consumer')

        # The read itself: the Id from Source's Get() reached Consumer's property.
        $consumerTest = $calls | Where-Object { $_.Method -eq 'Test' -and $_.Name -eq 'Consumer' } | Select-Object -First 1
        $consumerTest.Property.projectId | Should -Be 'proj-4711'
    }

    It "fails only the reading resource when it calls using() on a resource that declares no notify" {

        # No notify anywhere, so the gate's first arm fires. The run must survive: a throwing
        # property expansion is a per-resource failure, not an aborted file.
        $json = @'
{
  "parameters": {},
  "variables": {},
  "resources": [
    { "type": "Module/Source", "name": "Source", "properties": {} },
    { "type": "Module/Consumer", "name": "Consumer", "dependsOn": [ "Module/Source/Source" ], "properties": { "projectId": "$((using 'Module/Source/Source').Id)" } }
  ]
}
'@
        $config = New-ConfigFile -Name 'using-ungated.json' -Json $json
        $calls  = [System.Collections.Generic.List[object]]::new()
        $engine = New-UsingEngine -Calls $calls -GetOutputs @{ Source = [pscustomobject]@{ Id = 'proj-4711' } }

        $result = Start-DscRunner -FilePath $config -ConfigurationMode 'ApplyOnly' -DSCCompositeResourcePath $script:CompositeResourcePath -EngineAction $engine -ErrorAction SilentlyContinue

        $result.FailCount | Should -Be 1
        $failed = @($result.Results | Where-Object { $_.Status -eq 'FAIL' })
        $failed.InstanceName | Should -Be 'Consumer'

        # Source still ran and passed - the gate is per-resource.
        @($result.Results | Where-Object { $_.InstanceName -eq 'Source' }).Status | Should -Be 'OK'

        # And the reader never reached the engine's Test method.
        @($calls | Where-Object { $_.Method -eq 'Test' -and $_.Name -eq 'Consumer' }).Count | Should -Be 0
    }

    It "fails the reading resource when the notify declaration exists but names a different target" {

        # The second arm of the gate, and the one that makes using() a visibility rule rather
        # than an open lookup: Source notifies Other, so Consumer may not read it even though
        # Source's output is sitting in $script:resourceOutputs by the time Consumer runs.
        $json = @'
{
  "parameters": {},
  "variables": {},
  "resources": [
    { "type": "Module/Source", "name": "Source", "properties": {}, "notify": [ "Module/Other/Other" ] },
    { "type": "Module/Other", "name": "Other", "properties": {} },
    { "type": "Module/Consumer", "name": "Consumer", "dependsOn": [ "Module/Source/Source" ], "properties": { "projectId": "$((using 'Module/Source/Source').Id)" } }
  ]
}
'@
        $config = New-ConfigFile -Name 'using-wrong-target.json' -Json $json
        $calls  = [System.Collections.Generic.List[object]]::new()
        $engine = New-UsingEngine -Calls $calls -GetOutputs @{ Source = [pscustomobject]@{ Id = 'proj-4711' } }

        $result = Start-DscRunner -FilePath $config -ConfigurationMode 'ApplyOnly' -DSCCompositeResourcePath $script:CompositeResourcePath -EngineAction $engine -ErrorAction SilentlyContinue

        $failed = @($result.Results | Where-Object { $_.Status -eq 'FAIL' })
        $failed.InstanceName | Should -Be 'Consumer'

        # The declared target is unaffected.
        @($result.Results | Where-Object { $_.InstanceName -eq 'Other' }).Status | Should -Be 'OK'
    }
}
