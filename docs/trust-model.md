# Trust model and security boundary

> Ported from upstream `Dsc.PipelineRunner` (`docs/trust-model.md`). Upstream frames this as the
> canonical mirror of a `SECURITY.md` "Trust model" section; this repo has no `SECURITY.md` at
> the time of writing, so this page stands on its own here. Verified against
> `source/Private/Runner/Assert-SafeConditionExpression.ps1`, `Actions/Credential/*.ps1`,
> `Actions/Target/*.ps1` and `source/Private/DatumHelper/{Clone-Repository,Assert-SecureGitUrl}.ps1`
> as they exist in this repo; adjusted where the allow-list and the credential/target catalog
> have grown since upstream wrote this page.

## The one thing to remember

**`DSC.PipelineRunner.Akkodis` runs your configuration repository as trusted code.** If you would
not run a script from a source on your build agent as an administrator, do not point
`Invoke-DscRunner` (or the Azure-DevOps-flavored `Invoke-DscPipelineRunner`) at it.

## Why the configuration is code, not data

Datum merges YAML into per-node configuration, but the runner does not stop at data:

1. `Build-DatumConfiguration` executes a compile step that turns the merged configuration into a
   DSC `Configuration` block and runs it. A `Configuration` block is PowerShell — any statement
   valid in PowerShell is valid inside it.
2. Each resource may carry a `preCondition` (formerly `condition`; still accepted as a deprecated
   alias), a `postCondition`, a `preExecutionScript` and a `postExecutionScript`. All are compiled
   to script blocks and evaluated:
   - **`preCondition`** and **`postCondition`** are validated as *side-effect-free predicates*
     before they run (`Assert-SafeConditionExpression`). They may read variables and properties
     and compare them, and may call an explicit allow-list of function-language accessors —
     `parameters()`, `variables()`, `reference()`, `using()`, `nodeName()`,
     `configurationFile()`, `equals()`, `not()`, `concat()`, `empty()`, `coalesce()`,
     `toLower()`, `toUpper()`, `startsWith()`, `contains()`, and the arithmetic accessors
     (`add()`, `sub()`, `mul()`, `div()`, `mod()`, `min()`, `max()`, `int()`, `float()`) — every
     other command invocation, a variable assignment, or a method call is still rejected,
     including a disallowed command nested inside an allowed call (e.g.
     `equals(Get-Item C:\, 'x')`). `postCondition` additionally allow-lists `result()` (the
     `[DscMethodResult]` of the resource just applied) and `stopProcessing()` (sets the
     module-scope flag that stops the rest of the file from being processed) —
     `Assert-SafeConditionExpression -AllowStopProcessing` opts a single evaluation into that
     wider allow-list, and only `postCondition` ever passes that switch, so a `preCondition` can
     never see a result or halt the run. The full, current accessor list (including why there is
     no `secret()`) is documented in
     [WikiSource/Function-Language.md](../WikiSource/Function-Language.md). Both are run with the
     call operator (`&`) in a child scope, so they cannot rewrite the runner's own state other
     than through the allow-listed accessors.
   - **`preExecutionScript`** and **`postExecutionScript`** are imperative by design (they exist
     to call control verbs such as `Stop-TaskProcessing`/`stopProcessing()`) and are **not**
     constrained to a predicate grammar. Because they are unconstrained, a configuration may only
     declare either field when `PipelineRunnerSettings.AllowExecutionScripts: true` is set; a
     pre-parse rule rejects the whole run, naming every offending resource, when the gate is off.
     This is an explicit, all-or-nothing opt-in for the run — it is not a per-resource sandbox,
     and once enabled these scripts run with the same trust as the rest of the configuration.
     They run in a child scope, so they cannot silently rewrite the runner's locals, but they can
     execute arbitrary code. See
     [WikiSource/PipelineRunnerSettings.md § `AllowExecutionScripts`](../WikiSource/PipelineRunnerSettings.md).
3. The resources themselves are applied by the DSC engine (DSC v2 `Invoke-DscResource` or DSC v3
   `dsc`), which runs whatever the resource implementation does — locally by default, or against
   a `target`'s `CimSession`/`PSSession` when the resource (or the run's default) names a
   non-`Local` target (see "Remote targets and credentials" below).

## The boundary

| Boundary | Trusted side | Untrusted side |
|---|---|---|
| Configuration repository | Everything in it runs as code | — there is no untrusted side |
| Clone transport | HTTPS/SSH to a verified host | Plaintext HTTP — refused, not merely discouraged |
| Runner process | Runs configuration + resources | — |
| Remote target (`WinRM`/`SSH`) | The `computerName` and credential named by the configuration | Any host reachable from the build agent — the configuration decides which |

There is deliberately no "untrusted configuration" mode. Treat the configuration repository as
part of the trusted computing base.

## What the runner enforces

The clone is the one edge of this boundary the runner can defend on its own, and it does so
unconditionally — there is no setting that relaxes any of it (see `Clone-Repository.ps1` /
`Assert-SecureGitUrl.ps1`):

| Control | Behaviour |
|---|---|
| Transport | `https`, `ssh` and SCP-style `git@host:path` only. A plain `http://` URL throws a terminating error naming the scheme. |
| Revision pinning | `-ConfigurationRevision` checks out a branch, tag or commit. A full 40-character SHA is verified against the clone's resolved `HEAD`; a mismatch fails the run. |
| Provenance in the log | The resolved `HEAD` SHA is written to the information stream on every clone, so the pipeline log records the commit that actually ran. |
| Credential handling | Tokens are held as `[SecureString]` and injected as an HTTP `Authorization` header through git's environment-based configuration, never on the process command line, and redacted from error text. |
| Temporary directories | Clones are created owner-only and removed in a `finally`, so they do not survive a failed run. Only directories the runner created are removed — a caller-supplied path is never deleted. `-KeepTemporaryDirectory` opts out for debugging. |

This narrows the *transport*, not the boundary itself: a configuration delivered intact over a
verified channel still runs as fully-trusted code.

## Operational controls

- **Branch protection & required reviews** on the configuration repository, matching (or
  exceeding) the controls on the runner's own source.
- **Signed commits** where your platform supports enforcing them.
- **Scoped pipeline triggers** — restrict who can run the pipeline and from which branches.
- **Verified clone transport** — HTTPS or SSH with known-host verification. The runner already
  refuses anything else; keep host verification configured on the agent so the remote's identity
  is checked as well as its scheme.
- **Pin the revision** — pass `-ConfigurationRevision`, ideally a full commit SHA, so a push to
  the tracked branch cannot change what a run applies between review and execution.
- **Least privilege** on the agent identity and on any managed-node credentials — see
  [WikiSource/Remote-Targets-and-Credentials.md § "The identity the runner runs as"](../WikiSource/Remote-Targets-and-Credentials.md#the-identity-the-runner-runs-as).

## Remote targets and credentials

Two action hooks extend the boundary above from the build agent to the systems it manages
(`Invoke-Action`'s `ValidateSet`: `Source`, `Connect`, `Engine`, `Target`, `Credential`):

- **`Target`** (`Local`, `WinRM`, `SSH`) decides where a resource's DSC engine call runs.
  `Local` is a no-op (the resource runs in the runner's own process). `WinRM` opens a
  `New-CimSession`/`New-PSSession` pair against `Context.ComputerName`; `SSH` opens a
  `New-PSSession -SSHTransport` pair and fails fast if paired with the DSC v2 engine (SSH
  remoting requires DSC v3). Either way, a resource's `target.action` (or the run's
  `PipelineRunnerSettings.Target` default) names an arbitrary reachable host, so the
  "configuration repository is trusted code" boundary now extends over the network to every host
  the build agent can reach and has credentials for. Sessions are cached per
  `(target action, computer name, configuration name, credential)` for the file and always closed
  in a `finally` block, so a failed or interrupted run does not leak an open remote session.
- **`Credential`** (`Environment`, `Static`, `SecretManagement`) resolves the `[PSCredential]`
  used for a `target` connection or injected into a resource's `resourceCredential` property:
  - `Environment` (default) reads a username/password pair from two named environment variables
    (`UserNameVariable`/`PasswordVariable`) on the build agent — the secret value itself never
    appears in the configuration repository, only the names of the variables that hold it.
  - `Static` takes a plain-text or securestring password inline in the configuration and is
    intended for local development and testing only; every use emits a `Write-Warning` so it is
    visible in pipeline logs, and a plain-text value committed to the repository is exposed to
    anyone with read access to that repository's history.
  - `SecretManagement` resolves a named secret from a registered
    `Microsoft.PowerShell.SecretManagement` vault via `Get-Secret`, delegating the secret's
    storage, access control and rotation entirely to that vault. The runner holds the resolved
    value only as an in-memory `[PSCredential]` for the duration of the connection or resource
    application; it is not logged, cached to disk, or written to the compiled configuration.

For a resource applied through `DscV3`, a `[pscredential]`/`[securestring]` property is resolved
to plaintext immediately before building the `dsc resource <verb> --input` JSON payload — the one
place it is revealed — and force-redacted from the verbose log regardless of its property name.
See [WikiSource/Remote-Targets-and-Credentials.md § "Where a secret can appear"](../WikiSource/Remote-Targets-and-Credentials.md#where-a-secret-can-appear)
for the full table.

None of this narrows the core boundary — a configuration that can name a `target` and a
`Credential` action could always execute code with equivalent effect through the resources it
already declares. It documents where that trust now reaches, so operators can scope network
access and credential availability on the build agent accordingly.

## Future hardening (tracked)

- AST-based allow-listing of permitted DSC resource types.
- Executing the compile step under
  `[System.Management.Automation.SessionState]::LanguageMode = 'ConstrainedLanguage'`.

These would narrow the boundary but cannot remove it: a configuration that is allowed to declare
resources is, by construction, allowed to change the state those resources manage.

## See also

- [WikiSource/Function-Language.md](../WikiSource/Function-Language.md) — the full
  `preCondition`/`postCondition` accessor allow-list and why `secret()` is deliberately absent.
- [WikiSource/Remote-Targets-and-Credentials.md](../WikiSource/Remote-Targets-and-Credentials.md)
  — the full `Target`/`Credential` reference, including the identity the runner runs as and where
  a secret can appear in plaintext.
- [docs/remote-target-credential-handling.md](remote-target-credential-handling.md) — the design
  history of the `Credential` hook this page's boundary table relies on.
