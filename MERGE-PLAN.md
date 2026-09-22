# Merge Plan: AzDO-DSC-LCM ← Dsc.PipelineRunner

**Status:** Draft for review
**Source repos compared:**
- This repo (`AzDO-DSC-LCM`, module `DSC.PipelineRunner.Akkodis`) — commit `7fb9259` on `main`
- [`ZanattaMichael/Dsc.PipelineRunner`](https://github.com/ZanattaMichael/Dsc.PipelineRunner) (module `Dsc.PipelineRunner`) — `main` @ clone time

## 1. Why this merge

`Dsc.PipelineRunner` is a fork/successor of this codebase (same author, same Datum/pipeline-resource
lineage — file names like `Expand-HashTable.ps1`, `Sort-DependsOn.ps1`, `git.ps1` are byte-for-byte
recognisable). Its own [`docs/DECOUPLING_PLAN.md`](https://github.com/ZanattaMichael/Dsc.PipelineRunner/blob/main/docs/DECOUPLING_PLAN.md)
confirms the intent: strip Azure DevOps and "LCM" out of the core so the engine is a
platform-agnostic DSC pipeline runner. In doing that rewrite it gained a lot — but it also **dropped
four features this repo depends on**, because they didn't fit the new engine-agnostic loop shape at
the time and nobody ported them across:

| Feature | This repo | Dsc.PipelineRunner |
|---|:-:|:-:|
| Class-based resource model (`DSCConfigurationFile`, `DSCBaseResource`, `DSC_Resource`, `DSCStub`, `DSCCompositeResource`) | ✅ | ❌ (only `DscMethodResult`) |
| Stub / partial-resource merging (`merge_with`, `Merge-StubResources`) | ✅ | ❌ (no `Merge-StubResources` anywhere) |
| Composite resources (`type: composite/...`, linked `.yml`) | ✅ | ❌ (no composite handling at all) |
| Time-based / scheduled enforcement (`ConfigurationMode: Scheduled`, `ChangeWindows`, `Get-PipelineRunnerConfigurationMode`) | ✅ | ❌ (only `Mode: Test`/`Set`, no `ApplyOnly`/`Audit`/`Enforce`/`Scheduled`) |

Everything else in `Dsc.PipelineRunner` is a genuine upgrade over this repo's `Start-DscRunner` /
`Invoke-AZDoLCM` engine (see §3). The goal of this plan is to land on **this repo's feature set,
built on `Dsc.PipelineRunner`'s engine**, not to pick one repo over the other.

## 2. What we keep from this repo (non-negotiable per user instruction)

1. **Class-based logic** — `source/Classes/000-004*.ps1`, `source/Enum/000.ExecutionMethod.ps1`.
2. **Time-based LCM enforcement** — `Get-PipelineRunnerConfigurationMode.ps1`, `Get-HoursDifference.ps1`, the
   `ConfigurationMode: Scheduled` / `ChangeWindows` / `DaysOfWeek` Datum schema, and the
   `ApplyOnly` / `Audit` / `Enforce` vocabulary.
3. **Stub resources** — `DSCStub`, `merge_with`, `Merge-StubResources.ps1`, `mergable` flag on
   `DSC_Resource`.
4. **Composite resources** — `DSCCompositeResource`, `type: composite/<name>`, the
   `DSCCompositeResourcePath` / `CompositeResources` directory convention.

## 3. What we take from `Dsc.PipelineRunner` (the newer, better engine)

Grouped by theme, each with the source file(s):

**Execution engine abstraction**
- `Actions/Engine/DscV2.ps1`, `Actions/Engine/DscV3.ps1`, `Private/Actions/Invoke-EngineAction.ps1`,
  `Resolve-DscEngine.ps1`, `Test-DscV3ResourceType.ps1`, `ConvertTo-DscMethodResult.ps1`,
  `Classes/DscMethodResult.ps1`, `Public/ConvertTo-DscV3ConfigurationDocument.ps1`.
  Lets a resource run under classic `Invoke-DscResource` **or** `dsc.exe` (DSC v3), auto-detected or
  pinned, normalized to one result shape.

**Remote execution**
- `Actions/Target/{Local,SSH,WinRM}.ps1`, per-resource `target:` block, session caching keyed by
  `(action, computer, credential, endpoint)`, remote-vs-local reboot handling
  (`RebootRequired` + `Restart-Computer -Wait` on a remote target, fail-fast locally).

**Credential handling**
- `Actions/Credential/{Environment,SecretManagement,Static}.ps1`, `resourceCredential:` block,
  `Auth/Get-PipelineAuthToken.ps1`, `Auth/Unprotect-SecureString.ps1`,
  `Auth/ConvertTo-BasicAuthCredential.ps1`.

**Pluggable Source/Connect (extensibility seam)**
- `Actions/Source/{Local,Git}.ps1`, `Actions/Connect/{None,AzureDevOps}.ps1`,
  `Private/Actions/Invoke-Action.ps1` — the generic loader-driven hook pattern this repo's own
  `Invoke-CustomTask` / PreParse rules already use, generalized to Source/Connect/Engine/Target/
  Credential. `Invoke-DscRunner` (provider-agnostic entry point) sits alongside the
  Azure-DevOps-flavoured `Invoke-DscPipelineRunner`.

**Resource lifecycle additions**
- `preCondition` (renamed `condition`, back-compat alias kept), `postCondition` (new — asserts on
  the outcome, can call `stopProcessing()` / `result()`), `preExecutionScript` (new, mirrors
  existing `postExecutionScript`), `notify` / `using()` (Puppet/Chef-style change propagation —
  `Expand-NotifyDependsOn.ps1`, `script:notifyDeclarations` / `pendingNotifyRefresh` in
  `Start-DscRunner`).

**Function/condition language**
- `Private/Runner/{add,sub,mul,div,mod,min,max,int,float,coalesce,concat,contains,startsWith,
  toLower,toUpper,empty}.ps1` — arithmetic and string functions callable inside
  `parameters()`/`variables()`/conditions — plus `Assert-SafeConditionExpression.ps1` and
  `ConvertTo-NormalizedConditionExpression.ps1`, which allow-list what a condition/postCondition
  expression may do (no arbitrary commands/assignments — closes a code-injection surface this
  repo's `[scriptblock]::Create($task.Condition)` doesn't guard at all).

**Security hardening**
- `Assert-SecureGitUrl.ps1` (https/ssh only, rejects `http://`), commit-SHA pinning
  (`-ConfigurationRevision` verified against clone HEAD), owner-only temp directories +
  guaranteed cleanup in `finally` (`Register-/Remove-RunnerTemporaryDirectory`,
  `Set-PrivateDirectoryPermission.ps1`), path-traversal guard on `Build-DatumConfiguration
  -AllowedRoot`, `Test-ExecutionScriptsAllowed.ps1` (PreParse gate on `preExecutionScript`/
  `postExecutionScript` via `PipelineRunnerSettings.AllowExecutionScripts`).

**Reporting / operability**
- Structured `[pscustomobject]` run result (`Status`, `TotalResources`, `Pass/Fail/SkipCount`,
  `FailedResources`, `Results`) from `Start-DscRunner`, JSON **and** CSV reports, `Merge-DscRunnerResult`
  to summarize multiple config files, `-FailOnError` → non-zero exit code, `Write-Information`
  (tag `Dsc.PipelineRunner`) instead of `Write-Host` so output is redirectable/capturable,
  suppressed `$ProgressPreference` during a run.

**Robustness fixes worth inheriting regardless of feature scope**
- Case-insensitive JSON config loading (`ConvertTo-CaseInsensitiveHashtable`) — PS 7.3+ breaks
  mixed-case member access otherwise.
- Missing/empty configuration file is a terminating error, not a silent zero-resource "success".
- Circular-dependency detection bug fix (shared-stack pop bug — this repo's `Test-CircularReferences.ps1`
  should be diffed against the new one for the same defect).
- `PipelineRunnerSettings` block in `Datum.yml` (`Engine`, `Target`, `Reboot`,
  `AllowExecutionScripts`, `Source`, `Connect`) as the single place run-level knobs live —
  `Get-PipelineRunnerSetting.ps1`.

## 4. The core architectural tension — and how to resolve it

This repo's `Start-DscRunner` loop walks an array of **typed class instances** (`DSC_Resource` /
`DSCStub` / `DSCCompositeResource`, produced by `[DSCConfigurationFile]::New()` →
`ConvertTo-Resource`). `Dsc.PipelineRunner`'s `Start-DscRunner` loop walks **plain
hashtables/PSCustomObjects** straight off the parsed YAML/JSON, and every new capability
(`target`, `resourceCredential`, `preCondition`, `postCondition`, `notify`, engine selection) is a
new *ad-hoc key* read directly off that object — there is no class to extend.

Rewriting `Start-DscRunner`'s entire loop to operate on class instances would mean re-deriving
every feature in §3 against a stricter, harder-to-extend model. Converting the class hierarchy to
hashtables would drop §2. **Neither extreme is right.** The plan instead keeps classes exactly
where they already add value — parsing and pre-processing — and lets the engine loop keep
consuming plain objects:

```
 DSCConfigurationFile.Load()                     (unchanged: YAML/JSON → typed objects)
        │
        ▼
 ConvertTo-Resource                                (unchanged: dispatch by type/merge_with)
        │  emits DSC_Resource[] / DSCStub[] / DSCCompositeResource[]
        ▼
 Merge-StubResources  (stub merge, unchanged)
        │
 Expand-CompositeResources (NEW — see §5.3)         DSCCompositeResource → inlined DSC_Resource[]
        │
        ▼
 ConvertTo-PipelineTask (NEW, thin)                  DSC_Resource[] → plain [pscustomobject]/hashtable
        │                                            carrying every key Start-DscRunner already
        │                                            expects (name/type/properties/dependsOn/
        │                                            preCondition/postCondition/notify/target/
        │                                            resourceCredential/preExecutionScript/
        │                                            postExecutionScript/executionMethodOverride)
        ▼
 Expand-NotifyDependsOn → Sort-DependsOn → PreParse rules → Start-DscRunner (engine-agnostic loop, unchanged)
```

`DSC_Resource` gains the new optional properties it needs to carry through (`preCondition`,
`postCondition`, `notify`, `target`, `resourceCredential`, `preExecutionScript`) — additive changes,
no behavior change for existing configs that don't set them. `ConvertTo-PipelineTask` is a thin
projection (`$_.psobject` / hashtable copy of the class's public properties); it is the **only** new
seam, and it's small enough to unit-test exhaustively.

`ExecutionMethod` (`None`/`Test`/`Set` override per resource) is layered onto the engine loop the
same way it works today: read `executionMethodOverride` off the projected task, override
`$Mode` for that resource before calling `Invoke-EngineAction`.

## 5. Concrete integration steps

### 5.1 Module & manifest
- Decide module identity (see §7, open question). Recommendation: keep `DSC.PipelineRunner.Akkodis` as the
  module name (least disruptive for existing consumers/pipelines already pinned to it), but adopt
  `Dsc.PipelineRunner`'s manifest hygiene: drop `AzureDevOpsDsc*` from hard `RequiredModules`
  (already done here — confirm parity), add `PIPELINERUNNER_CACHE_DIRECTORY`-style generic env
  var with `AZDODSC_CACHE_DIRECTORY` kept as an alias, add `Sampler.GitHubTasks` to
  `RequiredModules.psd1` if the wiki-build task (§5.6) is adopted.
- Port `source/Private/Configuration/Resolve-CacheDirectory.ps1` and
  `source/Private/DatumHelper/{Assert-SecureGitUrl,Register-RunnerTemporaryDirectory,
  Remove-RunnerTemporaryDirectory,Set-PrivateDirectoryPermission}.ps1` verbatim.

### 5.2 Classes (extend, don't replace)
- `source/Classes/002.DSC_Resource.ps1`: add `[string]$preCondition`, `[string]$postCondition`,
  `[string]$preExecutionScript`, `[string[]]$notify`, `[hashtable]$target`,
  `[hashtable]$resourceCredential`. Keep `condition` as a back-compat alias for `preCondition`
  (mirror the new repo's own deprecation-warning pattern in `Start-DscRunner`).
- `source/Classes/003.DSCStub.ps1`, `004.DSCCompositeResource.ps1`: unchanged.
- New: `Expand-CompositeResources` (Custom rule, alongside `Merge-StubResources`) — walks any
  `DSCCompositeResource` in the task list, loads its linked `DSCConfigurationFile`, expands its
  inner resources with the composite's own parameter/variable scope, and splices the resulting
  `DSC_Resource[]` into the pipeline in place of the composite node. This is new code (today's
  `DSCCompositeResource` only *loads* the linked file — nothing currently expands it into the
  execution list; confirm this is in fact a pre-existing gap in this repo during implementation,
  since it changes the shape of work).

### 5.3 Engine & Actions (port wholesale)
- Copy `Actions/`, `source/Private/Actions/`, `source/Private/Auth/` directories as-is.
- Copy `source/Private/Runner/Start-DscRunner.ps1` → replaces `source/Private/LCM/Start-DscRunner.ps1`,
  with these deltas on top of the upstream version:
  - Accept `ConfigurationMode` (`ApplyOnly`/`Audit`/`Enforce`) in addition to `Mode` (`Test`/`Set`),
    matching this repo's existing `Start-DscRunner` signature — `ConfigurationMode` maps to `Mode` exactly
    as today's switch statement does, and is threaded into the report.
  - Re-apply the `ApplyOnly` vs `Enforce` re-test/verify branching from this repo's `Start-DscRunner`
    (lines ~266–319 of the current file) — `Dsc.PipelineRunner` has no equivalent because it never
    had those modes; this is new logic layered onto the ported loop, not a port itself.
  - Keep `-ContinueOnError` / `$failedResources` cascading dependency-skip logic from this repo —
    `Dsc.PipelineRunner` doesn't have it.
  - Read `executionMethodOverride` off the projected task (§4) the same way today's `Start-DscRunner` does.
- Copy `source/Private/Runner/*.ps1` (function-language + condition-safety files) wholesale.
- Copy `source/Classes/DscMethodResult.ps1`, `source/Private/Actions/ConvertTo-DscMethodResult.ps1`.

### 5.4 Time-based enforcement (port + rewire)
- Copy `Get-PipelineRunnerConfigurationMode.ps1` and `Get-HoursDifference.ps1` verbatim into
  `source/Private/LCM/` (or fold under `Private/Configuration/` to match the new repo's layout —
  pick one and apply consistently, see §7).
- `Invoke-DscLCM.ps1` (this repo's generic entry point) keeps resolving
  `ConfigurationMode` via `Get-PipelineRunnerConfigurationMode` before calling the ported `Start-DscRunner`,
  exactly as it does today against `Start-DscRunner`.
- Add `PipelineConfigurationMode` / `ChangeWindows` to the `PipelineRunnerSettings` schema section of
  the wiki docs being ported (§5.6), since `Dsc.PipelineRunner`'s `PipelineRunnerSettings` page
  doesn't know about it yet.

### 5.5 Stub & composite resources (port + integrate)
- Copy `Pipeline Rules/Custom/Merge-StubResources.ps1` verbatim; it already operates on the
  `[DSCStub]` type-check, so it's untouched by the engine swap.
- `Pipeline Rules/Custom/Sort-DependsOn.ps1`: diff against `Pipeline Rules/Custom/Sort-DependsOn.ps1`
  (125 lines vs. this repo's current version) — the new one has presumably picked up fixes (the
  circular-dependency backtracking bug mentioned in the new repo's CHANGELOG, §3). Port the new
  version, then re-verify stub/composite name resolution (`getFullResourceName()`,
  `type: composite/...`) still round-trips through it.
- Wire `Expand-CompositeResources` (§5.2) into the same pipeline stage as
  `Invoke-CustomTask -CustomTaskName "Merge-StubResources"` in `Start-DscRunner`, before
  `Expand-NotifyDependsOn`/`Sort-DependsOn` (composites must be expanded before dependency sort
  sees the real resource list).

### 5.6 PreParse rules
- Port `Pipeline Rules/PreParse/Test-ExecutionScriptsAllowed.ps1` (new security gate).
- Diff and reconcile `Test-CircularReferences.ps1` and `Test-ResourcesForIncorrectProperties.ps1`
  against this repo's versions; take the new repo's bug fixes, keep this repo's stub/composite
  awareness if the new version doesn't have it (it won't, since it has no concept of either).
- `Invoke-PreParseRules.ps1` gains the `-Settings` parameter (for `Test-ExecutionScriptsAllowed`
  to read `AllowExecutionScripts`).

### 5.7 Public entry points
- `Invoke-DscLCM.ps1` / `Invoke-AZDoLCM.ps1`: keep both names and both `ConfigurationMode`
  surfaces (this repo's contract), but internally delegate to the ported engine. Layer in
  `Invoke-DscRunner`'s Source/Connect action seam underneath `Invoke-AZDoLCM` *optionally* — i.e.
  `Invoke-AZDoLCM` keeps working exactly as today (direct Azure DevOps auth call), but gains the
  ability to accept `-ConfigurationRevision` pinning and `-KeepTemporaryDirectory` from the ported
  clone/cleanup code.
- Add `ConvertTo-DscV3ConfigurationDocument.ps1` and `Resolve-DscDatumProject.ps1` (rename check
  against this repo's `Resolve-AzDoDatumProject.ps1` — likely the same function renamed; keep this
  repo's name for back-compat, or alias both).

### 5.8 Docs & tests
- Port `WikiSource/*.md` and `docs/*.md`, editing out the "no LCM" framing (§7 open question) and
  re-adding the Scheduled/ChangeWindows, stub, and composite sections this repo's README/wiki
  already documents.
- Port `Tests/PipelineRunner/**` test files for every ported function 1:1, renaming
  `PipelineRunner` → this repo's `LCM` test-tree convention (or vice versa — pick one, see §7).
  Keep every existing `Tests/LCM/DSCConfiguration/Classes/*.tests.ps1` (stub/composite/class
  coverage) — these have no counterpart upstream and are the regression net for §2.
- New tests required (no upstream equivalent): `Expand-CompositeResources`, `ConvertTo-PipelineTask`,
  `Get-PipelineRunnerConfigurationMode` × new engine (Scheduled mode driving DscV3, Scheduled mode driving a
  remote target), stub-merge × notify/using interaction, composite resource × dependency sort.

## 6. Suggested phase/PR breakdown

1. **Plumbing, no behavior change.** Port `Actions/`, `Private/Actions/`, `Private/Auth/`,
   `Private/DatumHelper/*` additions, `Resolve-CacheDirectory`, `ConvertTo-CaseInsensitiveHashtable`,
   `DscMethodResult`. Nothing wired into `Start-DscRunner` yet; ships dead code behind no callers, but
   gets the large mechanical diff landed and reviewed on its own.
2. **Engine swap.** Replace `Start-DscRunner` with the ported `Start-DscRunner` (+ `ApplyOnly`/`Enforce`
   re-test branching, `ContinueOnError`), still consuming **hashtables** (no class changes yet) —
   proves the engine port is behavior-preserving for every existing non-stub/composite/scheduled
   config before classes re-enter the picture.
3. **Classes back in.** `ConvertTo-PipelineTask` projection, extended `DSC_Resource` properties,
   re-point `Invoke-DscLCM`/`Start-DscRunner` call site to consume the class pipeline's output.
4. **Stub + composite.** `Merge-StubResources` port, `Expand-CompositeResources` new rule, wired
   into the pipeline before notify/sort.
5. **Scheduled enforcement.** `Get-PipelineRunnerConfigurationMode` port + `ConfigurationMode` threading.
6. **New capabilities exposed.** Remote targets, credentials, notify/using, engine selection,
   function language — these mostly "just work" once step 2 lands, so this phase is chiefly docs +
   tests confirming they interact correctly with stub/composite/scheduled configs (§5.8's new
   test list).
7. **Docs, security hardening pass, cleanup.** Wiki port, `Assert-SafeConditionExpression` on
   existing `condition`/`postExecutionScript` usage, `Test-ExecutionScriptsAllowed` gate,
   `Assert-SecureGitUrl`, temp-dir hardening.

Each phase should be its own PR against `main` (or against this branch as a stacked series) so
review stays tractable — this is a large, multi-week merge, not a single patch.

## 7. Open questions for the user

- **Module identity:** keep `DSC.PipelineRunner.Akkodis` as the shipped name, or rename to align with
  `Dsc.PipelineRunner` (and if so, is Azure DevOps still the primary/only Connect provider you
  care about, or is the provider-agnostic `Invoke-DscRunner` entry point a goal in its own right)?
- **"LCM" terminology:** `Dsc.PipelineRunner` deliberately scrubbed "LCM" from its docs/code
  because it isn't a Windows DSC LCM. This repo's whole vocabulary (`Start-DscRunner`,
  `Get-PipelineRunnerConfigurationMode`, `PipelineConfigurationMode`, `Invoke-AZDoLCM`) is built on that term. Keep
  it (it's this repo's established public surface) or rename during the merge?
- **Test-tree layout:** `Tests/LCM/...` vs. `Tests/PipelineRunner/...` — align on one.
- **`Invoke-PreParseRules -Settings`:** confirm `AllowExecutionScripts` gating is desired for this
  repo's existing configs (some may already rely on `postExecutionScript`/`condition` scriptblocks
  that would need `PipelineRunnerSettings.AllowExecutionScripts: true` added to their `Datum.yml`
  to keep working under the ported PreParse rule).
- **Composite resource expansion:** confirm today's `DSCCompositeResource` is genuinely
  unexpanded before this merge (§5.2) — if it turns out there's expansion logic this research
  missed, `Expand-CompositeResources` becomes a port instead of new code.

## 8. File-level reference map

| This repo (today) | Action | `Dsc.PipelineRunner` source |
|---|---|---|
| `source/Private/LCM/Start-DscRunner.ps1` | Replace with ported + `ApplyOnly`/`Enforce`/`ContinueOnError` re-added | `source/Private/Runner/Start-DscRunner.ps1` |
| `source/Private/LCM/Get-PipelineRunnerConfigurationMode.ps1` | Keep, unchanged | *(none — new)* |
| `source/Private/Configuration/Get-HoursDifference.ps1` | Keep, unchanged | *(none — new)* |
| `source/Classes/00{0-4}.*.ps1` | Extend (see §5.2) | `source/Classes/DscMethodResult.ps1` (additive, not a replacement) |
| `source/Enum/000.ExecutionMethod.ps1` | Keep, unchanged | *(none — new)* |
| `Pipeline Rules/Custom/Merge-StubResources.ps1` | Keep, unchanged | *(none — new)* |
| `Pipeline Rules/Custom/Sort-DependsOn.ps1` | Port newer version, re-verify | `Pipeline Rules/Custom/Sort-DependsOn.ps1` |
| `Pipeline Rules/PreParse/Test-CircularReferences.ps1` | Diff + take fixes | `Pipeline Rules/PreParse/Test-CircularReferences.ps1` |
| `Pipeline Rules/PreParse/Test-ResourcesForIncorrectProperties.ps1` | Diff + take fixes | `Pipeline Rules/PreParse/Test-ResourcesForIncorrectProperties.ps1` |
| *(none)* | Add | `Pipeline Rules/Custom/Expand-NotifyDependsOn.ps1` |
| *(none)* | Add | `Pipeline Rules/PreParse/Test-ExecutionScriptsAllowed.ps1` |
| *(none)* | Add wholesale | `Actions/**` (Engine, Target, Source, Connect, Credential) |
| *(none)* | Add wholesale | `source/Private/Actions/**`, `source/Private/Auth/**` |
| *(none)* | Add | `source/Private/Runner/{add,sub,mul,div,mod,min,max,int,float,coalesce,concat,contains,startsWith,toLower,toUpper,empty,Assert-SafeConditionExpression,ConvertTo-NormalizedConditionExpression}.ps1` |
| `source/Private/DatumHelper/Clone-Repository.ps1`, `git.ps1` | Port hardened versions | same paths, `Assert-SecureGitUrl.ps1` added |
| *(none)* | Add | `source/Private/DatumHelper/{Register,Remove}-RunnerTemporaryDirectory.ps1`, `Set-PrivateDirectoryPermission.ps1` |
| *(none)* | Add | `source/Private/Configuration/{ConvertTo-CaseInsensitiveHashtable,Resolve-CacheDirectory,Get-PipelineRunnerSetting,Resolve-PipelineParameter}.ps1` |
| `source/Public/Invoke-DscLCM.ps1` | Keep name/contract, rewire internals | `source/Public/Invoke-DscRunner.ps1` (pattern reference) |
| `source/Public/Invoke-AZDoLCM.ps1` | Keep name/contract, rewire internals | `source/Public/Invoke-DscPipelineRunner.ps1` (pattern reference) |
| `source/Public/Resolve-AzDoDatumProject.ps1` | Confirm parity | `source/Public/Resolve-DscDatumProject.ps1` |
| *(none)* | Add | `source/Public/ConvertTo-DscV3ConfigurationDocument.ps1` |
| `source/Public/VersionConfiguration.ps1`, `Build-DatumConfiguration.ps1`, `Test-DatumConfiguration.ps1`, `Stop-TaskProcessing.ps1` | Diff, take hardening fixes (`AllowedRoot` path-traversal guard, `SourceIsRemote` warning) | same paths |

---
*This plan is research + design only — no source has been merged yet. Implementation should
proceed phase-by-phase per §6, each phase reviewed and tested independently before the next
begins.*
