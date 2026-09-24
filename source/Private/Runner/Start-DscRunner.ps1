<#
.SYNOPSIS
Invokes the Desired State Configuration (DSC) based on a provided configuration file.

.DESCRIPTION
The Start-DscRunner function processes a DSC configuration file (YAML or JSON) and executes the
tasks defined within it. It keeps this repo's class-based parsing (stub resources, composite
resources, and the ApplyOnly/Audit/Enforce/ContinueOnError vocabulary), and runs each resource
through Dsc.PipelineRunner's engine-agnostic loop: Test/Set/Get dispatch via Invoke-EngineAction
(DscV2 / DscV3 / a custom engine), remote target/session handling, credential resolution,
preCondition/postCondition, pre/post execution scripts, and notify/using() change propagation.

Pipeline shape (see MERGE-PLAN.md §4-5):

  [DSCConfigurationFile]::New()  (unchanged: YAML/JSON -> typed class instances)
        -> Merge-StubResources    (unchanged: stub merge by 'mergable'/'merge_with')
        -> Expand-CompositeResources (DSCCompositeResource -> inlined DSC_Resource[], each tagged with its composite's scope)
        -> ConvertTo-PipelineTask (NEW, thin: DSC_Resource -> plain [pscustomobject])
        -> Expand-NotifyDependsOn -> Sort-DependsOn -> PreParse rules -> this engine-agnostic loop

Each resource is evaluated through the selected engine, which returns a normalized
[DscMethodResult]. All human-readable output is emitted on the information stream
(Write-Information, tag 'DSC.PipelineRunner.Akkodis') rather than Write-Host, so a caller can
capture it with -InformationVariable or redirect it. DSC's native progress UI is suppressed for
the duration of the run.

.PARAMETER FilePath
The path to the compiled per-node configuration file (.yaml/.yml or .json).

.PARAMETER ConfigurationMode
The mode of operation for the runner: 'ApplyOnly' (Set, no re-verify), 'Audit' (Test only) or
'Enforce' (Set, then re-Test to verify the change actually landed). Maps to the engine's
Test/Set 'Mode' exactly as it always has in this repo.

.PARAMETER ReportPath
Optional directory for saving the report. When provided, a CSV report is written for the
configuration.

.PARAMETER DSCCompositeResourcePath
Directory that composite resource .yml files (referenced via `type: composite/<name>`) are
resolved against. Passed straight through to [DSCConfigurationFile]::New().

.PARAMETER ContinueOnError
When specified, a resource failure does not stop processing. Resources that directly or
transitively depend on the failed resource are automatically marked as failed and skipped; all
other resources continue to run. Without this switch, the first Set failure halts all
subsequent task processing (matching this repo's historical behavior).

.PARAMETER Engine
Execution engine action (Actions/Engine/<Engine>.ps1). 'Auto' opts in to detection; default is
Invoke-DscResource (DscV2).

.PARAMETER EngineVersion
Optional resource version hint that biases 'Auto' engine selection by major version.

.PARAMETER EngineAction
Optional inline engine override; takes precedence over -Engine.

.PARAMETER RunnerSettings
Resolved PipelineRunnerSettings (e.g. AllowExecutionScripts, Reboot, Target). Invoke-DscRunner
resolves this once from Datum.yml and passes it through; every key is optional and defaulted, so
omitting it preserves this repo's historical local-only, scripts-disabled-by-PreParse behavior.

.OUTPUTS
[pscustomobject] describing the run: ConfigurationFile, Status (Completed / StoppedByRequest /
AbortedByException), TotalResources, PassCount, FailCount, SkipCount, DurationSeconds,
ErrorMessage, FailedResources and the per-resource Results.

.EXAMPLE
Start-DscRunner -FilePath "C:\Configs\MyConfig.yaml" -ConfigurationMode "Audit" -DSCCompositeResourcePath "C:\Composite"

.EXAMPLE
Start-DscRunner -FilePath "C:\Configs\MyConfig.yaml" -ConfigurationMode "Enforce" -ContinueOnError -DSCCompositeResourcePath "C:\Composite"
Runs in Enforce mode; if a resource fails its Set operation, dependent resources are skipped but independent resources continue.

.NOTES
- The function processes tasks in the order of their dependencies.
- The function generates a detailed report of the execution, which can be saved to a specified path.
#>
function Start-DscRunner {
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")]
        [string] $ConfigurationMode,

        [String] $ReportPath = $null,

        [Parameter(Mandatory = $true)]
        [string] $DSCCompositeResourcePath,

        [switch] $ContinueOnError,

        [string] $Engine = 'DscV2',
        [string] $EngineVersion,
        [scriptblock] $EngineAction,

        [hashtable] $RunnerSettings = @{}
    )

    # Informational output is the pipeline log's signal channel; make it visible by default
    # for the duration of the run, and keep DSC's native progress UI out of the log. Both are
    # local to this scope, so the caller's preferences are left untouched on return.
    $InformationPreference = 'Continue'
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    $infoTag = 'DSC.PipelineRunner.Akkodis'

    # ConfigurationMode -> engine Mode, exactly as this repo's original Start-DscRunner always mapped it.
    $Mode = $( switch ($ConfigurationMode) {
        "ApplyOnly" { "Set" }
        "Audit"     { "Test" }
        "Enforce"   { "Set" }
        default     { "Test" }
    })

    Write-Verbose "Configuration Mode: $ConfigurationMode, Execution Mode: $Mode"

    # Resolve the engine once so any dsc.exe probe / auto-selection warning happens a single
    # time per file rather than per resource.
    $resolvedEngine = $Engine
    if (-not $EngineAction -and $Engine -eq 'Auto') {
        $resolvedEngine = Resolve-DscEngine -Engine $Engine -Version $EngineVersion
        Write-Verbose "Auto-selected DSC engine: $resolvedEngine"
    }
    $engineArgs = @{ Engine = $resolvedEngine }
    if ($EngineAction) { $engineArgs.EngineAction = $EngineAction }

    # Reset the run-control flag for this file. $script:StopTaskProcessing is a cross-file,
    # module-script-scope contract: Start-DscRunner owns it (reset here, read once per
    # resource below), and Stop-TaskProcessing is the only other writer.
    $script:StopTaskProcessing = $false

    # notify/using(): reset the per-run state that ties notify declarations, Get() output and
    # forced-refresh requests to this file.
    $script:notifyDeclarations = @{}
    $script:resourceOutputs = @{}
    $script:pendingNotifyRefresh = @{}
    $script:currentResourceKey = $null

    # Sessions opened by a Target action, cached per (TargetAction, ComputerName,
    # CredentialKey) so multiple resources aimed at the same remote target reuse one
    # connection. Closed in the finally block below regardless of how the run ends.
    $sessionCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $rebootPolicy = if ($RunnerSettings -and -not [string]::IsNullOrWhiteSpace([string]$RunnerSettings['Reboot'])) { [string]$RunnerSettings['Reboot'] } else { 'Fail' }
    $defaultTargetAction = if ($RunnerSettings -and -not [string]::IsNullOrWhiteSpace([string]$RunnerSettings['Target'])) { [string]$RunnerSettings['Target'] } else { 'Local' }

    # Track resource names that have failed (used when -ContinueOnError is active), keyed by
    # the same "Type/Name" identity Sort-DependsOn/DependsOn use.
    $failedResources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Clear any existing data in the module's shared parameter/variable/reference hashtables
    # before populating them for this file.
    $parameters.Clear()
    $variables.Clear()
    $references.Clear()

    $configName = (Split-Path -Leaf $FilePath) -replace '\.(yml|yaml|json)$', ''

    $reportSummary   = [System.Collections.Generic.List[pscustomobject]]::new()
    $resultIndex     = [System.Collections.Generic.Dictionary[string, pscustomobject]]::new([System.StringComparer]::Ordinal)
    $runStatus       = 'Completed'
    $runError        = $null
    $runStopwatch    = [System.Diagnostics.Stopwatch]::StartNew()

    # Records a single resource outcome, replacing any earlier record for the same tuple so a
    # resource re-observed within a file does not double-count.
    $recordResult = {
        param($ResourceType, $InstanceName, $Status, $DurationMs, $ErrorMessage)

        $recordedTarget       = $targetAction
        $recordedComputerName = if ($session) { $session.ComputerName } else { $null }
        $recordedReboot       = if ($result) { [bool]$result.RebootRequired } else { $false }

        $record = [pscustomobject]@{
            NodeName          = $configName
            ResourceType      = $ResourceType
            InstanceName      = $InstanceName
            ConfigurationFile = $FilePath
            Status            = $Status
            DurationMs        = $DurationMs
            ErrorMessage      = $ErrorMessage
            Target            = $recordedTarget
            ComputerName      = $recordedComputerName
            RebootRequired    = $recordedReboot
        }

        $key = '{0}|{1}|{2}' -f $FilePath, $ResourceType, $InstanceName
        if ($resultIndex.ContainsKey($key)) {
            $reportSummary[$reportSummary.IndexOf($resultIndex[$key])] = $record
        }
        else {
            $reportSummary.Add($record)
        }
        $resultIndex[$key] = $record
    }

    Write-Information "---------------------------------------------------------------------" -Tags $infoTag
    Write-Information "  Runner: $configName   [ConfigurationMode: $ConfigurationMode, Engine: $resolvedEngine]" -Tags $infoTag
    Write-Information "---------------------------------------------------------------------" -Tags $infoTag

    # Class-based parsing: YAML/JSON -> typed instances, with stub/composite resolution.
    $pipeline = [DSCConfigurationFile]::New($FilePath, $DSCCompositeResourcePath)

    Write-Information "--> Setting Variables:" -Tags $infoTag

    # Pipeline's parameter default values must land in $parameters so property/variable
    # expansion (Expand-HashTable/Expand-Parameters) and conditions can resolve them.
    if ($pipeline.parameters) {
        $defaultValues = GetDefaultValues -Source $pipeline.parameters
        SetVariables -Source $defaultValues -Target $parameters
    }
    if ($pipeline.variables) {
        SetVariables -Source $pipeline.variables -Target $variables
    }

    Write-Information "--> Merging partial (stub) resources:" -Tags $infoTag
    $tasks = Invoke-CustomTask -Tasks $pipeline.resources -CustomTaskName "Merge-StubResources"

    Write-Information "--> Expanding composite resources:" -Tags $infoTag
    $tasks = Invoke-CustomTask -Tasks $tasks -CustomTaskName "Expand-CompositeResources"

    # Thin projection: typed DSC_Resource instances -> plain [pscustomobject]s the rest of the
    # pipeline (ported from Dsc.PipelineRunner) already expects.
    $tasks = @($tasks | ConvertTo-PipelineTask)

    Write-Information "--> Expanding notify declarations:" -Tags $infoTag
    $tasks = Invoke-CustomTask -Tasks $tasks -CustomTaskName "Expand-NotifyDependsOn"

    # Build the source-resource-key -> notify-targets map that using() consults to gate access.
    foreach ($notifySource in $tasks) {
        if (-not $notifySource.Notify) { continue }
        $notifySourceKey = "$($notifySource.type)/$($notifySource.name)"
        $script:notifyDeclarations[$notifySourceKey] = @($notifySource.Notify | ForEach-Object { $_.Trim() })
    }

    Write-Information "--> Sorting tasks based on dependencies:" -Tags $infoTag
    $tasks = Invoke-CustomTask -Tasks $tasks -CustomTaskName "Sort-DependsOn"

    Write-Information "--> Processing PreParse Rules:" -Tags $infoTag
    Invoke-PreParseRules -Tasks $tasks -Settings $RunnerSettings

    Write-Information "--> Processing Formatting Tasks:" -Tags $infoTag
    $tasks = Invoke-FormatTasks -Tasks $tasks

    $totalTasks = @($tasks).Count
    $TaskCounter = 0

    # Run context for the nodeName() / configurationFile() accessors (called from a
    # [scriptblock]::Create block, which does not see this function's locals).
    $script:currentNodeName          = $configName
    $script:currentConfigurationFile = $FilePath

    # The file's own parameters/variables. Set-CompositeScope restores these before each
    # resource and layers a composite's own values on top for resources that came from one.
    $baselineParameters = @{} + $parameters
    $baselineVariables  = @{} + $variables

    try {
        foreach ($task in $tasks) {

            $TaskCounter++
            Set-CompositeScope -CompositeScope $task.CompositeScope -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables
            $resourceKey = "$($task.type)/$($task.name)"
            $resourceStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $targetAction = $defaultTargetAction
            $session = $null
            $result = $null
            $script:currentResourceKey = $resourceKey

            Write-Verbose "Processing resource: [$resourceKey]"

            if ($Script:StopTaskProcessing) {
                Write-Verbose "Skipping resource due to 'Stop-TaskProcessing' being called:"
                $runStatus = 'StoppedByRequest'
                & $recordResult $task.type $task.name 'SKIP' 0 "Resource skipped due to 'Stop-TaskProcessing' cmdlet."
                Write-Information ("[{0}/{1}] SKIP {2} (stopped by request)" -f $TaskCounter, $totalTasks, $resourceKey) -Tags $infoTag
                continue
            }

            # -ContinueOnError cascade: if any dependency has already failed, skip this
            # resource too and mark it failed so the cascade continues to its own dependents.
            if ($ContinueOnError -and $task.DependsOn -and @($task.DependsOn).Count -gt 0) {
                $failedDep = @($task.DependsOn) | Where-Object { $failedResources.Contains($_) } | Select-Object -First 1
                if ($null -ne $failedDep) {
                    Write-Verbose "Skipping resource [$resourceKey] - dependency '$failedDep' failed."
                    & $recordResult $task.type $task.name 'SKIP' 0 "Resource skipped because dependency '$failedDep' failed."
                    Write-Information ("[{0}/{1}] SKIP {2} (dependency '{3}' failed)" -f $TaskCounter, $totalTasks, $resourceKey, $failedDep) -Tags $infoTag
                    $null = $failedResources.Add($resourceKey)
                    continue
                }
            }

            # preCondition (back-compat alias: condition). A predicate, not a program:
            # Assert-SafeConditionExpression rejects any command, assignment or method call
            # before it runs.
            $preConditionExpression = $null
            if ($null -ne $task.PreCondition) {
                $preConditionExpression = $task.PreCondition
            }
            elseif ($null -ne $task.Condition) {
                $preConditionExpression = $task.Condition
            }

            if ($null -ne $preConditionExpression) {
                try {
                    Assert-SafeConditionExpression -Expression $preConditionExpression
                    $sbCondition = [scriptblock]::Create((ConvertTo-NormalizedConditionExpression -Expression $preConditionExpression))
                    $conditionResult = & $sbCondition
                }
                catch {
                    Write-Error "[Start-DscRunner] Could not evaluate the preCondition of resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                    & $recordResult $task.type $task.name 'FAIL' $resourceStopwatch.ElapsedMilliseconds $_.Exception.Message
                    Write-Information ("[{0}/{1}] FAIL {2} ({3}ms) - {4}" -f $TaskCounter, $totalTasks, $resourceKey, $resourceStopwatch.ElapsedMilliseconds, $_.Exception.Message) -Tags $infoTag
                    if (-not $ContinueOnError) { $script:StopTaskProcessing = $true }
                    else { $null = $failedResources.Add($resourceKey) }
                    continue
                }

                if ($conditionResult -eq $false) {
                    Write-Verbose "Skipping resource due to preCondition: [$resourceKey]"
                    & $recordResult $task.type $task.name 'SKIP' $resourceStopwatch.ElapsedMilliseconds "Resource skipped due to preCondition {$preConditionExpression}."
                    Write-Information ("[{0}/{1}] SKIP {2} (preCondition)" -f $TaskCounter, $totalTasks, $resourceKey) -Tags $infoTag
                    continue
                }
            }

            $module = $task.type.Split("/")[0]
            $resourceType = $task.type.Split("/")[1]

            $resourceStatus = 'OK'
            $resourceError = $null

            try {
                $Property = Expand-HashTable -InputHashTable (Expand-Parameters -InputHashTable $task.properties)

                # A declarative 'resourceCredential' block resolves a credential through the
                # Credential hook and injects it into the resource's own properties.
                if ($null -ne $task.ResourceCredential) {
                    $credentialContext = $task.ResourceCredential
                    $credentialActionName = if (-not [string]::IsNullOrWhiteSpace([string]$credentialContext.action)) { [string]$credentialContext.action } else { 'Environment' }
                    $resolvedResourceCredential = Invoke-Action -Hook Credential -Name $credentialActionName -Context $credentialContext
                    $targetPropertyName = if (-not [string]::IsNullOrWhiteSpace([string]$credentialContext.propertyName)) { [string]$credentialContext.propertyName } else { 'Credential' }
                    $Property[$targetPropertyName] = $resolvedResourceCredential
                }
            }
            catch {
                Write-Error "[Start-DscRunner] Could not resolve the properties of resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                & $recordResult $task.type $task.name 'FAIL' $resourceStopwatch.ElapsedMilliseconds $_.Exception.Message
                Write-Information ("[{0}/{1}] FAIL {2} ({3}ms) - {4}" -f $TaskCounter, $totalTasks, $resourceKey, $resourceStopwatch.ElapsedMilliseconds, $_.Exception.Message) -Tags $infoTag
                if ($ContinueOnError) { $null = $failedResources.Add($resourceKey) } else { $script:StopTaskProcessing = $true }
                continue
            }

            # Resolve this resource's execution target. A per-resource 'target' block
            # overrides the file/settings-level default. 'Local' never invokes the Target
            # hook, so an unmodified configuration's local-only execution path is untouched.
            $targetAction = if ($task.Target -and -not [string]::IsNullOrWhiteSpace([string]$task.Target.action)) { [string]$task.Target.action } else { $defaultTargetAction }
            $session = $null

            if ($targetAction -ne 'Local') {
                try {
                    $targetCredential = $null
                    $credentialCacheKey = ''
                    if ($task.Target.credential) {
                        $tCred = $task.Target.credential
                        $tCredAction = if (-not [string]::IsNullOrWhiteSpace([string]$tCred.action)) { [string]$tCred.action } else { 'Environment' }
                        $targetCredential = Invoke-Action -Hook Credential -Name $tCredAction -Context $tCred
                        $credentialCacheKey = "$tCredAction|$($tCred.Name)|$($tCred.UserNameVariable)"
                    }

                    $targetContext = @{
                        ComputerName      = [string]$task.Target.computerName
                        Engine            = $resolvedEngine
                        Credential        = $targetCredential
                        ConfigurationName = [string]$task.Target.configurationName
                    }

                    $sessionCacheKey = "$targetAction|$($targetContext.ComputerName)|$($targetContext.ConfigurationName)|$credentialCacheKey"
                    if (-not $sessionCache.ContainsKey($sessionCacheKey)) {
                        $sessionCache[$sessionCacheKey] = Invoke-Action -Hook Target -Name $targetAction -Context $targetContext
                    }
                    $session = $sessionCache[$sessionCacheKey]
                }
                catch {
                    Write-Error "[Start-DscRunner] Could not establish the '$targetAction' target for resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                    & $recordResult $task.type $task.name 'FAIL' $resourceStopwatch.ElapsedMilliseconds $_.Exception.Message
                    Write-Information ("[{0}/{1}] FAIL {2} ({3}ms) - {4}" -f $TaskCounter, $totalTasks, $resourceKey, $resourceStopwatch.ElapsedMilliseconds, $_.Exception.Message) -Tags $infoTag
                    if ($ContinueOnError) { $null = $failedResources.Add($resourceKey) } else { $script:StopTaskProcessing = $true }
                    continue
                }
            }
            if ($session) { $engineArgs.Session = $session } else { $engineArgs.Remove('Session') }

            # preExecutionScript runs immediately before the Test/Set evaluation. Invoked with
            # &, not dot-sourced, so it cannot rewrite this function's own locals.
            if ($null -ne $task.PreExecutionScript) {
                $sbPreExecutionScript = [scriptblock]::Create($task.PreExecutionScript)
                & $sbPreExecutionScript
            }

            # Determine the per-resource execution method override, same as this repo has
            # always supported.
            $ExecutionMode = $Mode
            if ($task.ExecutionMethodOverride -and $task.ExecutionMethodOverride -ne 'None') {
                $ExecutionMode = $task.ExecutionMethodOverride
            }

            try {
                $result = Invoke-EngineAction -Method 'Test' -ModuleName $module -Name $resourceType -Property $Property @engineArgs
            }
            catch {
                Write-Error "[Start-DscRunner] 'Test' method failed for resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                & $recordResult $task.type $task.name 'FAIL' $resourceStopwatch.ElapsedMilliseconds $_.Exception.Message
                Write-Information ("[{0}/{1}] FAIL {2} ({3}ms) - {4}" -f $TaskCounter, $totalTasks, $resourceKey, $resourceStopwatch.ElapsedMilliseconds, $_.Exception.Message) -Tags $infoTag
                if ($ContinueOnError) { $null = $failedResources.Add($resourceKey) } else { $script:StopTaskProcessing = $true }
                continue
            }

            # notify/using(): a resource notified by a genuinely-changed notifier is forced to
            # re-run Set() this pass even if its own Test() reports it is already OK.
            $neededChange = -not $result.InDesiredState
            $forcedByNotify = ($ExecutionMode -eq "Set") -and $script:pendingNotifyRefresh.Contains($resourceKey)

            $CurrentTaskState = 'Continue'
            $didSet = $false

            if ($result.InDesiredState -and -not $forcedByNotify) {
                $resourceStatus = 'OK'
            }
            elseif ($ExecutionMode -eq "Test") {
                # Drift detected but this resource is Test-only: report drift, don't apply.
                $resourceStatus = 'FAIL'
                $resourceError = $result.Message
            }
            elseif ($ExecutionMode -eq "Set") {
                $didSet = $true
                try {
                    $result = Invoke-EngineAction -Method 'Set' -ModuleName $module -Name $resourceType -Property $Property @engineArgs
                    $resourceStatus = 'OK'

                    # Reboot handling: a remote target restarts itself and waits; a local
                    # target cannot safely do that mid-run, so it fails and stops the file
                    # unless RunnerSettings.Reboot is explicitly 'Ignore'.
                    if ($result.RebootRequired) {
                        if ($session -and $session.IsRemote) {
                            Write-Information "Reboot required on remote target [$($session.ComputerName)] after resource [$resourceKey]; restarting and waiting..." -Tags $infoTag
                            $restartParams = @{ ComputerName = $session.ComputerName; Wait = $true; Force = $true; ErrorAction = 'Stop' }
                            if ($task.Target.credential -and $session.PSSession -and $session.PSSession.Credential) {
                                $restartParams.Credential = $session.PSSession.Credential
                            }
                            Restart-Computer @restartParams
                        }
                        elseif ($rebootPolicy -eq 'Ignore') {
                            Write-Information "Resource [$resourceKey] requires a reboot; RunnerSettings.Reboot is 'Ignore', continuing without restarting." -Tags $infoTag
                        }
                        else {
                            $resourceStatus = 'FAIL'
                            $resourceError = "Resource [$resourceKey] requires a reboot to complete, and the local host cannot safely restart itself mid-run. Set RunnerSettings.Reboot: Ignore to continue without restarting, or target this resource at a remote computer."
                            Write-Error "[Start-DscRunner] $resourceError" -ErrorAction Continue
                            $CurrentTaskState = 'Stop'
                        }
                    }
                }
                catch {
                    Write-Error "[Start-DscRunner] Failed to apply changes with 'Set' method: [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                    $resourceStatus = 'FAIL'
                    $resourceError = $_.Exception.Message
                    $CurrentTaskState = 'Stop'
                }
            }

            # ApplyOnly vs Enforce re-test/verify branching (this repo's original behavior;
            # Dsc.PipelineRunner has no equivalent since it never had these modes). Gated on
            # $didSet, not just $ExecutionMode -eq 'Set', so a resource already in the desired
            # state on its first Test (no Set attempted) isn't re-tested a second time for
            # nothing.
            if (($CurrentTaskState -eq 'Continue') -and ($ConfigurationMode -eq 'Enforce') -and $didSet -and ($resourceStatus -eq 'OK')) {
                try {
                    $verifyResult = Invoke-EngineAction -Method 'Test' -ModuleName $module -Name $resourceType -Property $Property @engineArgs
                    if ($verifyResult.InDesiredState) {
                        $resourceStatus = 'OK'
                    }
                    else {
                        $resourceStatus = 'FAIL'
                        $resourceError = "Resource [$resourceKey] was set, but re-verification (ConfigurationMode 'Enforce') shows it is still not in the desired state."
                        $CurrentTaskState = 'Stop'
                    }
                }
                catch {
                    Write-Error "[Start-DscRunner] Failed to re-verify resource under 'Enforce' mode: [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                    $resourceStatus = 'FAIL'
                    $resourceError = $_.Exception.Message
                    $CurrentTaskState = 'Stop'
                }
            }
            # ApplyOnly: the Set result stands without re-verification (by design).

            # notify/using(): only a genuine change that completed successfully propagates a
            # forced refresh onward to whatever this resource itself notifies.
            if ($neededChange -and $resourceStatus -eq 'OK' -and $script:notifyDeclarations.Contains($resourceKey)) {
                foreach ($notifyTarget in $script:notifyDeclarations[$resourceKey]) {
                    $script:pendingNotifyRefresh[$notifyTarget] = $true
                }
            }

            # postCondition: asserts on the outcome (via result()/stopProcessing()); a $false
            # result marks the resource FAIL regardless of what the engine itself reported.
            if ($null -ne $task.PostCondition) {
                $script:currentResourceResult = $result
                try {
                    Assert-SafeConditionExpression -Expression $task.PostCondition -AllowStopProcessing
                    $sbPostCondition = [scriptblock]::Create((ConvertTo-NormalizedConditionExpression -Expression $task.PostCondition))
                    $postConditionResult = & $sbPostCondition
                }
                catch {
                    Write-Error "[Start-DscRunner] Could not evaluate the postCondition of resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                    $resourceStatus = 'FAIL'
                    $resourceError = $_.Exception.Message
                    $postConditionResult = $null
                }
                finally {
                    $script:currentResourceResult = $null
                }

                if ($postConditionResult -eq $false) {
                    $resourceStatus = 'FAIL'
                    $resourceError = "Resource failed postCondition {$($task.PostCondition)}."
                }
            }

            # postExecutionScript: invoked with &, not dot-sourced, so it can read runner
            # variables/call control verbs (e.g. Stop-TaskProcessing) but cannot rewrite this
            # function's own locals or report.
            if ($null -ne $task.PostExecutionScript) {
                $sbPostExecutionScript = [scriptblock]::Create($task.PostExecutionScript)
                & $sbPostExecutionScript
            }

            # Get: retrieve current state for the references table. A failed Get should not
            # abort the run.
            try {
                $getResult = Invoke-EngineAction -Method 'Get' -ModuleName $module -Name $resourceType -Property $Property @engineArgs
                $output_var = $getResult.Raw
            }
            catch {
                Write-Error "[Start-DscRunner] 'Get' method failed for resource [$resourceKey]: $($_.Exception.Message)" -ErrorAction Continue
                $output_var = $null
            }

            $references[$task.name] = $output_var
            $script:resourceOutputs[$resourceKey] = $output_var

            $resourceStopwatch.Stop()
            & $recordResult $task.type $task.name $resourceStatus $resourceStopwatch.ElapsedMilliseconds $resourceError
            Write-Information ("[{0}/{1}] {2} {3} ({4}ms)" -f $TaskCounter, $totalTasks, $resourceStatus, $resourceKey, $resourceStopwatch.ElapsedMilliseconds) -Tags $infoTag

            # Handle task failure: either stop all processing or track the failure for
            # dependency cascading, per -ContinueOnError.
            if ($CurrentTaskState -eq 'Stop' -or $resourceStatus -eq 'FAIL') {
                if ($ContinueOnError) {
                    $null = $failedResources.Add($resourceKey)
                }
                elseif ($CurrentTaskState -eq 'Stop') {
                    $script:StopTaskProcessing = $true
                }
            }
        }
    }
    catch {
        $runStatus = 'AbortedByException'
        $runError = $_.Exception.Message
        Write-Error "[Start-DscRunner] Run aborted by an unexpected error: $($_.Exception.Message)" -ErrorAction Continue
    }
    finally {

        $runStopwatch.Stop()
        $ProgressPreference = $previousProgressPreference

        $script:currentNodeName          = $null
        $script:currentConfigurationFile = $null

        # Drop the last resource's composite layer so it does not outlive this file.
        Set-CompositeScope -CompositeScope @() -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        foreach ($cachedSession in $sessionCache.Values) {
            if ($cachedSession.CimSession) {
                Remove-CimSession -CimSession $cachedSession.CimSession -ErrorAction SilentlyContinue
            }
            if ($cachedSession.PSSession) {
                Remove-PSSession -Session $cachedSession.PSSession -ErrorAction SilentlyContinue
            }
        }

        $passCount = @($reportSummary | Where-Object { $_.Status -eq 'OK' }).Count
        $failCount = @($reportSummary | Where-Object { $_.Status -eq 'FAIL' }).Count
        $skipCount = @($reportSummary | Where-Object { $_.Status -eq 'SKIP' }).Count
        $failedResourceRecords = @($reportSummary | Where-Object { $_.Status -eq 'FAIL' })

        if ($ReportPath) {
            $csvPath = [System.IO.Path]::Combine($ReportPath, ("{0}.csv" -f $configName))
            $reportSummary | Export-Csv -Path $csvPath -NoTypeInformation
        }

        # This final human-facing run summary uses Write-Host (not Write-Information like the
        # per-resource lines above) so it always reaches the console/pipeline log regardless of
        # $InformationPreference - matching the original Start-DscRunner's summary behavior.
        Write-Host "DSC Configuration Report: $FilePath"
        Write-Host "Run Status: $runStatus"

        foreach ($record in $reportSummary) {
            Write-Host ("[{0}] {1}/{2} - Result: [{3}]" -f $record.NodeName, $record.ResourceType, $record.InstanceName, $record.Status)
        }

        Write-Host "Total Tasks Executed: $($reportSummary.Count)"
        Write-Host "Tasks Passed:  $passCount"
        Write-Host "Tasks Failed:  $failCount"
        Write-Host "Tasks Skipped: $skipCount"

        if ($failedResourceRecords.Count -gt 0) {
            Write-Host "Failed Resources:"
            foreach ($failed in $failedResourceRecords) {
                Write-Host ("  {0}/{1} [{2}] - {3}" -f $failed.ResourceType, $failed.InstanceName, $failed.ConfigurationFile, $failed.ErrorMessage)
            }
        }
    }

    # Structured run result so callers (Invoke-DscRunner / Invoke-DscPipelineRunner) can
    # aggregate outcomes across configuration files via Merge-DscRunnerResult.
    return [pscustomobject]@{
        ConfigurationFile = $FilePath
        NodeName          = $configName
        Status            = $runStatus
        TotalResources    = $reportSummary.Count
        PassCount         = $passCount
        FailCount         = $failCount
        SkipCount         = $skipCount
        DurationSeconds   = [math]::Round($runStopwatch.Elapsed.TotalSeconds, 3)
        ErrorMessage      = $runError
        FailedResources   = $failedResourceRecords
        Results           = $reportSummary
    }
}
