# Lifecycle scripting extensions and reboot handling — design record

> **Adaptation note.** Ported from upstream `Dsc.PipelineRunner` (`docs/lifecycle-scripting-and-reboot-handling.md`).
> Upstream's own text already frames this as a design record rather than current documentation
> ("Both have since shipped, so this document is kept as the design record"), and that holds in
> this repo too: `preCondition`/`postCondition`/`preExecutionScript`/`result()`/`stopProcessing()`
> and the reboot policy described below are all implemented in
> `source/Private/Runner/Start-DscRunner.ps1` and `source/Private/Runner/Assert-SafeConditionExpression.ps1`.
> One correction to make explicit: §2.4's allow-list proposal names only the original five
> accessors plus `result`/`stopProcessing`; the allow-list as shipped in this repo is
> considerably larger (string/collection helpers, arithmetic, `nodeName()`/`configurationFile()`,
> `using()`) — see [WikiSource/Function-Language.md](../WikiSource/Function-Language.md) for the
> current, authoritative list. For the current, non-historical description of the whole
> per-resource sequence, see
> [WikiSource/Execution-Lifecycle.md](../WikiSource/Execution-Lifecycle.md).

Two related follow-on design questions against the resource lifecycle described in
`Start-DscRunner.ps1` and the function language covered in
[`docs/dsc-v3-config-functions.md`](dsc-v3-config-functions.md):

1. Broaden the runner's own function language (`parameters()`, `variables()`, `reference()`,
   `equals()`, `not()`) to more of the lifecycle — rename `condition` to `preCondition`, add a
   `postCondition`, add a symmetrical `preExecutionScript`, and add `stopProcessing()` as a
   callable function — with `postExecutionScript`/`preExecutionScript` staying the deliberate
   exception (full imperative script, not the constrained function language).
2. A plan for "wait until a reboot has completed, then continue" for configurations that target
   computers — genuinely open at the time this was written, because the runner had no
   remote-execution story then, which changes what "wait" can mean.

Both have since shipped, so this document is kept as the design record rather than as a current
description of the code. The first landed as designed: `preCondition`/`postCondition`/
`preExecutionScript`, plus the `result()` and `stopProcessing()` accessors (and considerably more
accessors besides — see the adaptation note above). The second landed in a simpler form than §3
plans below — fail-and-stop, or `PipelineRunnerSettings.Reboot: Ignore`, for local targets rather
than §3.3's checkpoint/resume, and an in-process `Restart-Computer -Wait -Force` for remote
targets along the lines of §3.4, now that remoting support (`Actions/Target/{WinRM,SSH}.ps1`)
exists. Read `Start-DscRunner.ps1` and
[WikiSource/Remote-Targets-and-Credentials.md § "Reboots on a remote target"](../WikiSource/Remote-Targets-and-Credentials.md)
for what the runner does today; the line references below point at the code as it stood when
this was written and are approximate.

## 1. Current lifecycle shape (baseline, at time of writing)

From `Start-DscRunner.ps1`, per resource, in order:

1. `condition` — a predicate. Parsed as PowerShell, gated by `Assert-SafeConditionExpression`,
   which rejects any `CommandAst` (command invocation), `AssignmentStatementAst`, or
   `InvokeMemberExpressionAst`. Because it forbids **all** command invocations, real condition
   usage at the time was limited to bare comparisons — not the function-language style
   (`equals(...)`, `parameters(...)`) documented for property expansion, because `parameters
   ('Name')` parses as a `CommandAst` and would be rejected outright. That's the gap §2 closes:
   the function language exists, but it's unusable from `condition`.
2. `properties` resolution (`Expand-Parameters` → `Expand-HashTable`) — this is where
   `parameters()`/`variables()`/`reference()`/`equals()`/`not()` are actually usable, since
   `ExpandString` has no safety gate.
3. Engine `Test` (`Invoke-EngineAction -Method Test`).
4. Engine `Set` (if not in desired state and `Mode -eq 'Set'`).
5. `postExecutionScript` — a `[scriptblock]`, invoked with `&` (child scope), completely
   unrestricted: it may call commands, including `Stop-TaskProcessing`.
6. Engine `Get`, result stored into `$references`.

`Stop-TaskProcessing` is a public cmdlet, callable only from `postExecutionScript` at the time
(its own call-stack guard requires `Start-DscRunner` to be an ancestor frame, but nothing
currently stops it being wired into a condition — except that a condition can't invoke *any*
command, `condition` included, so in practice it's `postExecutionScript`-only).

## 2. Extending the function language into conditions

### 2.1 Rename `condition` → `preCondition`

Straightforward rename, `condition` kept as a back-compat alias (both read into the same
evaluation path in `Start-DscRunner`). No other file in the repo reads `condition` directly
(`Sort-DependsOn.ps1`, pre-parse rules don't touch it), so this was contained entirely to
`Start-DscRunner.ps1`'s condition-evaluation block. Semantics are unchanged: evaluated before
`Test`; `$false` skips (`SKIP`) the resource and moves to the next.

### 2.2 Add `postCondition`

A second predicate, evaluated **after** `Test`/`Set` resolve for this resource but **before**
`postExecutionScript` runs (so `postExecutionScript` can still see/react to whatever
`postCondition` decided). Unlike `preCondition`, a `postCondition` cannot skip the resource — it
already ran — so its effect is: a `$false` result marks the resource `FAIL` in the report
regardless of what the engine reported (a post-hoc verification gate, e.g. "the engine says this
succeeded, but does the *combination* of this resource's outcome and an earlier resource's
`reference()` output actually make sense"). This is genuinely new expressive power — nothing
before this lets a condition read *this resource's own* engine result.

To make that useful, the function language needed one more read-only accessor:

- **`result()`** — with no argument, returns the current resource's `[DscMethodResult]` from the
  most recent `Test`/`Set` call (so `postCondition` can write
  `not (equals (result().InDesiredState) $true)` or `$(result().RebootRequired)`). Scoped to
  `postCondition` only — `preCondition` runs before any engine call exists for this resource, so
  `result()` there is a defined error ("no result yet"), not `$null`, to avoid a silently-always-
  false condition.

### 2.3 Add `preExecutionScript`

Symmetrical to `postExecutionScript`: an unrestricted `[scriptblock]`, invoked with `&` before
`Test`, for imperative pre-flight work (logging, environment prep, calling `Stop-TaskProcessing`
to bail before even attempting a resource). Same trust level and same child-scope invocation as
`postExecutionScript` — no new safety mechanism needed here, it's explicitly the
non-function-language, "just PowerShell" escape hatch. Position in the loop: immediately after
`preCondition` passes, before property expansion, so it can also observe/react to `$task` before
properties are resolved.

### 2.4 `stopProcessing()` as a function-language extension

This was the one piece that needed a real security decision, not just plumbing, because
`Stop-TaskProcessing` is a *side effect* (it mutates `$script:StopTaskProcessing`), and the entire
point of `Assert-SafeConditionExpression` is that a condition must not be able to mutate runner
state.

Design (as shipped, with the allow-list since grown considerably beyond what's listed here — see
the adaptation note at the top of this page):

- `Assert-SafeConditionExpression` changed from "reject every `CommandAst`" to "reject every
  `CommandAst` whose command name is not in an explicit allow-list", where the allow-list is
  exactly the runner's function-language surface. `AssignmentStatementAst` and
  `InvokeMemberExpressionAst` stay unconditionally forbidden — the whitelist only widens which
  *named, reviewed* functions can be invoked, not what kind of AST node is allowed. Because
  `FindAll` walks nested nodes, an arbitrary command nested inside, say, an argument to
  `equals(...)` is still caught — only the outer call itself needs to match the whitelist, and
  every `CommandAst` in the tree (nested or not) is checked individually.
- **`stopProcessing()` is only permitted inside `postCondition`, not `preCondition`.** Rationale:
  `preCondition` runs before the resource has been evaluated at all, so a
  `preCondition: $(stopProcessing())`-style expression would halt the whole remaining run based
  on something that hasn't happened yet — surprising, and arguably the wrong tool (an author who
  wants to stop before a resource runs can already do that via `preExecutionScript`, which is
  unrestricted). `postCondition` is the natural fit: "given what actually happened, stop here."
  A parameter on `Assert-SafeConditionExpression` (`-AllowStopProcessing`) gates this, so
  `preCondition` calls it with the flag off and `postCondition` with it on — one function, one
  security check, context-dependent policy.
- A thin wrapper (`source/Private/Runner/stopProcessing.ps1`, alias `stopProcessing`) calls the
  existing `Stop-TaskProcessing` (reusing its call-stack guard unchanged) and returns `$true`, so
  it composes into a boolean expression: `postCondition: not(result().InDesiredState) -and
  stopProcessing()` reads naturally as "if this resource ended up wrong, stop the run" while
  still yielding a boolean for the `postCondition` result itself.

This is a deliberate, reviewed carve-out from "conditions are side-effect free" — it's not "any
side effect," it's exactly one reviewed, single-purpose, already-guarded function.

### 2.5 What stayed out of scope here

- DSC v3's own native `[functionName(...)]` syntax
  ([`docs/dsc-v3-config-functions.md`](dsc-v3-config-functions.md)) is a *property*-only concept
  — it has no notion of a runner-level `preCondition`/`postCondition`, so it is not part of this
  extension. The two function languages stay where they already apply: runner functions in
  `preCondition`/`postCondition`/`properties`, DSC v3 native functions in `properties` only (if
  and when `Native` mode ships).
- `preExecutionScript`/`postExecutionScript` stay fully imperative, as asked — no attempt to fold
  them into the constrained grammar. They remain the place for anything the function language
  can't express.

## 3. Reboot handling

### 3.1 Why this was harder than it looked: no remote-execution story at the time

At the time this was written, both engines ran **locally**, against whatever machine the runner
process itself was on — there was no `-ComputerName`/`-CimSession`/remote-target parameter
anywhere. That mattered directly for "wait for reboot": if the machine that reboots is the same
machine running the runner process, the process (and the CI/agent job hosting it) is killed by
the reboot. There is no in-process way to "wait" through your own machine's restart.

This meant the two sub-cases needed different solutions, and the answer depended on whether the
runner ever gained remote-target execution:

- **Local target**: reboot ends the current run. The only thing the runner can do is checkpoint
  cleanly and let something *outside* the current process resume it after boot — or, as actually
  shipped, simply fail and stop (or, with `PipelineRunnerSettings.Reboot: Ignore`, continue
  without restarting).
- **Remote target** (now shipped): the runner's own process, running on a controller that is not
  the node being configured, survives the target's reboot. `Restart-Computer -Wait -Force`
  against the target's session — a stock PowerShell cmdlet — solves this directly, because it's
  designed to restart a computer and block the *calling* session until it's reachable again.

### 3.2 A concrete bug this plan flagged: `RebootRequired` was modeled but discarded

`[DscMethodResult]` already had a `RebootRequired` field, populated correctly by
`Actions/Engine/DscV2.ps1` from `Invoke-DscResource`'s `Set` output, but at the time:

- `Start-DscRunner`'s `Set` call discarded the result, reboot flag included — nothing downstream
  ever saw it.
- `Actions/Engine/DscV3.ps1` hardcoded `RebootRequired = $false` unconditionally.

As shipped, both are fixed: `Start-DscRunner` keeps the `Set` result and acts on
`RebootRequired` (§3.4/§3 below), and `Actions/Engine/DscV3.ps1` now reads a `rebootRequired`
signal tolerantly from either a top-level boolean or a nested `metadata.'Microsoft.DSC'`
envelope, defaulting to `$false` when neither is present — the exact `dsc.exe` shape for this
was (and still is) unconfirmed against a real reboot-signalling resource.

### 3.3 Local-target plan: checkpoint + externally-orchestrated resume (not what shipped)

The plan below (a `StopAndCheckpoint`/`-ResumeFrom` mechanism with a 3010 exit code) is preserved
as historical context for the trade-offs it weighs, but it is **not what shipped**. What actually
shipped for a local target is the simpler `PipelineRunnerSettings.Reboot` policy
(`Fail` default / `Ignore`) described in
[WikiSource/PipelineRunnerSettings.md § `Reboot`](../WikiSource/PipelineRunnerSettings.md) — no
checkpoint file, no `-ResumeFrom`, no 3010 convention. If a checkpoint/resume mechanism is wanted
in the future, the design considerations below (atomic checkpoint writes, secret redaction in the
checkpoint, idempotent re-evaluation on resume) still apply and are worth re-reading before
building it:

1. A new `Actions/Reboot/<Name>.ps1` hook, following the existing `Source`/`Connect`/`Engine`
   pattern, with `StopAndCheckpoint` writing an atomic checkpoint (file path, mode, completed
   resources and their results, `$parameters`/`$variables`/`$references`), a new `PendingReboot`
   run status, and a `3010`-style exit code convention (the Windows "success, restart required"
   convention used by MSI and Windows Update).
2. A `-ResumeFrom <checkpointPath>` parameter reloading the checkpoint and skipping already-
   completed resources.
3. The reboot itself, and re-invoking the runner afterward, staying outside the module —
   `RunOnce` keys, a service, a scheduled task, or a self-hosted agent's own restart/reconnect
   behavior, consistent with the "no LCM" boundary this project holds elsewhere.
4. An opt-in `LocalRestartAndResume` variant that has the runner itself call
   `Restart-Computer -Force`, still requiring an external supervisor to relaunch with
   `-ResumeFrom`.

### 3.4 Remote-target plan (now shipped, in a simpler form)

What was sketched here as a future option is close to what actually shipped: when a `Set()`
reports `RebootRequired` and the resource ran against a remote target (a session with
`IsRemote = $true`), `Start-DscRunner` calls `Restart-Computer -ComputerName <target> -Wait
-Force` (reusing the target's credential when one was supplied) and then continues to the next
resource in the same loop — the runner's own process, on the controller, never went down. This
happens **regardless of `PipelineRunnerSettings.Reboot`**, since that policy only governs what
happens when the *local* host would need to restart itself. See
[WikiSource/Remote-Targets-and-Credentials.md § "Reboots on a remote target"](../WikiSource/Remote-Targets-and-Credentials.md).

### 3.5 Open questions from the original plan (status as of this repo)

- Should `PendingReboot` count as a "clean" outcome for `-FailOnError`? Moot as shipped — there
  is no `PendingReboot` run status in this repo; a local reboot requirement with `Reboot: Fail`
  (the default) simply fails and stops the file like any other resource failure.
- Does a checkpoint file need the same secret-redaction treatment `Protect-SensitiveValue`
  applies elsewhere? Also moot as shipped — there is no checkpoint file.
- Exact `dsc.exe` reboot-pending JSON shape for `DscV3.ps1`'s fix — still open; see §3.2 above.

## See also

- [WikiSource/Execution-Lifecycle.md](../WikiSource/Execution-Lifecycle.md) — the current,
  authoritative per-resource sequence, including `preCondition`/`postCondition`/reboot handling.
- [WikiSource/Function-Language.md](../WikiSource/Function-Language.md) — `result()` and
  `stopProcessing()` documented alongside the full, current accessor list.
- [WikiSource/Remote-Targets-and-Credentials.md](../WikiSource/Remote-Targets-and-Credentials.md)
  — reboot behavior on a remote target, as shipped.
- [WikiSource/PipelineRunnerSettings.md](../WikiSource/PipelineRunnerSettings.md) — the
  `Reboot`/`AllowExecutionScripts` settings, as shipped.
