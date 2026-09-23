# Remote-target execution and credential handling — design history

> **Status: implemented, but not exactly as designed here.** This document was ported from
> upstream `Dsc.PipelineRunner` (`docs/remote-target-credential-handling.md`), where it opened
> with "Nothing here is implemented yet." In **this repo**, the `Target` and `Credential` action
> hooks it proposes have since shipped — `Actions/Target/{Local,SSH,WinRM}.ps1` and
> `Actions/Credential/{Environment,SecretManagement,Static}.ps1` all exist and are wired into
> `Start-DscRunner.ps1` and `Invoke-Action`'s `ValidateSet` (`'Source'`, `'Connect'`, `'Engine'`,
> `'Target'`, `'Credential'`).
>
> The shipped shape differs from several specifics proposed below — most notably, the
> `Environment` credential handler takes explicit `UserNameVariable`/`PasswordVariable` context
> keys rather than deriving `DSCRUNNER_CREDENTIAL_<NAME>_USERNAME`/`..._PASSWORD` from a bare
> `Name`, and the config surface is `target`/`resourceCredential` blocks with an `action` key
> rather than top-level `PipelineRunnerSettings.Target`/`Credential` selecting the file-level
> handler alone. **For the authoritative, current documentation of what actually shipped, see
> [WikiSource/Remote-Targets-and-Credentials.md](../WikiSource/Remote-Targets-and-Credentials.md)
> and [WikiSource/Engines.md](../WikiSource/Engines.md).** This page is kept for the design
> rationale — *why* credential retrieval needed to be a pluggable hook at all — which still holds
> even though the concrete contract shipped differently.

Originally written as a follow-on design for issue #57 §4/§5 in the upstream project, following
the same `Actions/<Hook>/<Name>.ps1` pattern already used for `Source`, `Connect` and `Engine`.

## 1. Why credential handling needs its own hook

The original sketch had the caller pass the actual secret straight into a context hashtable,
mirroring `-ConnectContext`/`-SourceContext`. That's workable for a single hardcoded PAT
(`Actions/Connect/AzureDevOps.ps1`), but a remote target's connection credential needs to come
from *wherever the operator's secret actually lives* — an environment variable on a hosted
agent, a secret store (`Microsoft.PowerShell.SecretManagement`), a cloud key vault, a
file-based credential on a self-hosted box — and the runner has no business knowing which.
That's exactly the shape of problem `Source`/`Connect`/`Engine` already solve by being pluggable
actions rather than hardcoded logic in `Start-DscRunner.ps1`. Credential *retrieval* is the same:
a `Credential` hook, resolved by name, that the runner calls at the point a target needs
authenticating — not a value the caller pre-fetches and threads through parameters by hand.

This also keeps a deliberate boundary intact: the compiled Datum YAML only ever carries a
credential **reference** (a `credential`/`resourceCredential` block naming an action and its
lookup keys), never material. The difference is *how* that reference resolves to a
`[PSCredential]`/`[SecureString]` at run time — via a handler the runner invokes, not a hashtable
the caller pre-populated.

## 2. The `Credential` hook, as shipped

`Credential` is in `Invoke-Action`'s `ValidateSet` alongside `Source`, `Connect`, `Engine` and
`Target`, following the file pattern exactly: `Actions/Credential/<Name>.ps1`, invoked as
`& $actionPath -Context $Context`, returning a `[PSCredential]` (or, for the built-in handlers,
always a `[PSCredential]` — none of the three shipped `Credential` actions returns a bare
`[SecureString]`, unlike this plan's original proposal).

### 2.1 Handler contract, as shipped

- **Input** — a `-Context` hashtable, populated entirely from the YAML `credential`/
  `resourceCredential` block (plus `action`, which selects the handler file and is stripped
  before the rest is handed through). There is no separate `Purpose`/`-CredentialContext`
  parameter layer as originally proposed — each block is self-contained and handler-specific.
- **Output** — a `[PSCredential]`. `Static`'s `Password` key may be a plain string or an existing
  `SecureString`; `SecretManagement` wraps a bare `SecureString` secret into a `PSCredential`
  using a `userName` key (or the secret's own name).
- Resolution is cached per `(action, computerName, configurationName, credential)` for a
  `target` session, and re-resolved per resource for `resourceCredential` (it's declarative
  data on the resource, not a session-scoped lookup) — see
  [WikiSource/Remote-Targets-and-Credentials.md § "Session caching"](../WikiSource/Remote-Targets-and-Credentials.md).

### 2.2 Built-in handlers, as shipped

- **`Environment`** (default) — `Actions/Credential/Environment.ps1`. Takes explicit
  `UserNameVariable`/`PasswordVariable` context keys (not a `Name`-derived convention), reads
  them via `[Environment]::GetEnvironmentVariable`, and wraps the password with
  `ConvertTo-SecureString -AsPlainText -Force` to build the `[PSCredential]`. Zero external
  dependencies — works out of the box on any hosted or self-hosted agent that can set job-scoped
  environment variables.
- **`SecretManagement`** — soft dependency on `Microsoft.PowerShell.SecretManagement`, matching
  the soft-dependency shape `Actions/Connect/AzureDevOps.ps1` uses. Calls `Get-Secret -Name
  $Context.name -Vault $Context.vault`. This is the recommended answer for "I already have a
  vault" without the runner needing a bespoke integration per provider.
- **`Static`** (opt-in, non-production) — accepts `UserName`/`Password` placed directly in the
  YAML block. Emits a `Write-Warning` on *every* use, steering authors toward `Environment`/
  `SecretManagement` for anything checked into a pipeline definition.

A custom handler is just another `Actions/Credential/<Name>.ps1` file — a bespoke internal vault
integration doesn't need a PR against this module.

## 3. Where the two consumers call the handler

- **Connection credential** (`target.credential`, `Actions/Target/{WinRM,SSH}.ps1`) — resolved
  once when the session is built, fed to `New-CimSession -Credential`/`New-PSSession
  -Credential` (WinRM) or the SSH session constructor. Cached with the session per
  `(action, computerName, configurationName, credential)`, so re-resolving on every resource
  against the same target machine doesn't happen.
- **Resource-property credential** (`resourceCredential`, primarily for `DscV3`) — resolved per
  resource, written into the expanded property table under `propertyName` (default `Credential`)
  immediately before the target is resolved. `Actions/Engine/DscV3.ps1` then resolves a
  `[PSCredential]`/`[SecureString]` property to `{username, password}` (or plaintext)
  immediately before building the `--input` JSON payload — the plaintext is routed through
  `Test-SensitivePropertyName`/`Protect-SensitiveValue` before any `Write-Verbose`, and
  force-redacted regardless of the property's name. `DscV2` keeps using native `MSFT_Credential`
  marshaling over the encrypted WinRM transport — no plaintext exposure, no handler-specific
  logging concern.

## 4. What stayed out of scope

Consistent with the original plan:

- Fan-out (resolving one credential reference across a list of target machines) is out of scope
  — each `target`/`resourceCredential` block resolves against the one computer it names.
- Credential *rotation*/expiry handling is not addressed — a handler is called fresh per cache
  miss, so a vault-backed handler naturally picks up a rotated secret on the next file/run;
  there's no in-run refresh of a cached session's credential if it expires mid-file.

## See also

- [WikiSource/Remote-Targets-and-Credentials.md](../WikiSource/Remote-Targets-and-Credentials.md)
  — the current, authoritative reference for `Target`/`Credential` actions, the identity the
  runner runs as, session caching, and where a secret can appear in plaintext.
- [WikiSource/Engines.md](../WikiSource/Engines.md) — how a resolved target session feeds into
  `DscV2`/`DscV3`.
- [docs/lifecycle-scripting-and-reboot-handling.md](lifecycle-scripting-and-reboot-handling.md) —
  the reboot story this document's remote-target work made possible.
