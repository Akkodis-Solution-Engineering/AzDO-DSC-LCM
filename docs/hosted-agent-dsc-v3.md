# Getting started on a hosted Linux agent with DSC v3

> **Applicability note.** This page was ported from upstream `Dsc.PipelineRunner`
> (`docs/hosted-agent-dsc-v3.md`). Upstream's bootstrap tooling — `scripts/Install-DscV3.ps1`,
> the `containers/dsc-agent` image, and a dedicated `DSC v3 Hosted Agent` CI workflow — was not
> part of what was merged into this repo and is **not present here**. The `DscV3` engine itself
> (`Actions/Engine/DscV3.ps1`) is fully implemented and usable; what's missing is upstream's
> convenience tooling for *installing* the `dsc` executable on a fresh agent. Section 1 below is
> adjusted accordingly — install `dsc` yourself (Microsoft's own instructions, or your own
> bootstrap step) rather than via a bundled script.

`Invoke-DscResource` (DSC **v2**) is Windows- and PowerShell-first. DSC **v3** ships a
standalone, cross-platform command-line engine (`dsc`) that runs on Linux, macOS and Windows.
Running the pipeline runner's **DscV3** engine on a hosted Linux agent is what makes
cloud-hosted, ephemeral agents genuinely useful — no Windows box required.

This page covers three things:

1. Installing `dsc` on a fresh agent.
2. Running `Invoke-DscRunner` (or the Azure-DevOps-flavored `Invoke-DscPipelineRunner`) with the
   DSC v3 engine.
3. Pipeline-native authentication for a git configuration source, including workload-identity
   federation (no long-lived PATs).

---

## 1. Install the DSC v3 engine

There is no bundled bootstrap script in this repo. Install `dsc` per
[Microsoft's own instructions](https://learn.microsoft.com/powershell/dsc/) for your platform —
typically downloading the release archive matching your agent's OS/architecture from the
[PowerShell/DSC releases](https://github.com/PowerShell/DSC/releases) page and adding it to
`PATH` for the job, or building your own hosted-agent image with `dsc` pre-installed.

Verify:

```powershell
dsc --version
dsc resource list
```

`source/Private/Actions/Test-DscExecutableAvailable.ps1` is what the runner itself uses to probe
for `dsc` on `PATH` when `-Engine Auto` is selected (see `Resolve-DscEngine.ps1`) — if that probe
finds it, so will your own smoke test above.

---

## 2. Run with the DSC v3 engine

Select the engine explicitly, or let the runner choose. `-exportConfigDir` is mandatory on both
entry points — it is where Datum's per-node compile output lands.

```powershell
# Explicit — always use the DSC v3 (dsc) engine.
Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath .\config -Engine DscV3

# Auto — pick DscV3 when dsc is present (or PipelineRunnerSettings.DSCResourceVersion / the
# -EngineVersion hint decides by major version: 3.x -> DscV3), otherwise fall back to DscV2.
Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath .\config -Engine Auto
```

When `-Engine` is not passed at all, `Invoke-DscRunner` falls through to
`PipelineRunnerSettings.Engine` from the configuration's `Datum.yml`, and only then to the
default `DscV2` — it does not implicitly resolve `Auto` on your behalf. See
[WikiSource/Engines.md](../WikiSource/Engines.md#selecting-one) for the exact precedence order.

### Cache directory

Neither entry point needs a cache environment variable for the runner's own operation — it uses
a temporary directory by default. Some referenced *resources* may still read one, so if your
configuration relies on `PIPELINERUNNER_CACHE_DIRECTORY` (the current name; the Azure-DevOps-era
`AZDODSC_CACHE_DIRECTORY` is still honoured as a back-compat alias — see
`source/Private/Configuration/Resolve-CacheDirectory.ps1`), set it before the run:

```powershell
$env:PIPELINERUNNER_CACHE_DIRECTORY = "$PWD/.cache"
```

---

## 3. Pipeline-native authentication

When the configuration source is a private git repository, the runner needs a credential to
clone it. This repo has two authentication paths, and they are not interchangeable:

- **`Invoke-DscPipelineRunner -JITToken $token`** — the Azure-DevOps-flavored entry point. The
  token is mandatory (`-JITToken` has no environment-variable fallback of its own); pass the
  job's own `$(System.AccessToken)` explicitly. Internally it sets `$script:JITToken`, which the
  module's `git` wrapper (`source/Private/DatumHelper/git.ps1`) reads to inject the credential as
  an HTTP `Authorization` header through git's environment-based config (`GIT_CONFIG_*`) — never
  on the process command line — and redacts it from error text.
- **The generic `Source`/`Git` action** (`Invoke-Action -Hook Source -Name Git -Context @{ Url =
  $repoUrl }`, backed by `Actions/Source/Git.ps1`) — this is the path that auto-detects a token:
  an explicit `Context.Token` takes precedence, and when none is supplied it falls back to
  `$env:SYSTEM_ACCESSTOKEN` via `Get-PipelineAuthToken`. Use this when you want the
  provider-agnostic entry point (`Invoke-DscRunner`, called with a local directory that this
  action resolved) without wiring a token through by hand.

`Invoke-DscRunner` called directly with a git URL in `-ConfigurationSourcePath` clones through
`Clone-Repository` the same way, but has no `-Token`/`-SourceContext` parameter of its own in
this repo — it relies on `$script:JITToken` already being set in the calling scope (which is
exactly what `Invoke-DscPipelineRunner` does for you). If you're not going through
`Invoke-DscPipelineRunner`, resolve the source explicitly via the `Source`/`Git` action first:

```powershell
$dir = Invoke-Action -Hook Source -Name Git -Context @{ Url = $repoUrl; Revision = $sha }
Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath $dir -Engine DscV3
```

Two things hold for every clone regardless of which path you use, and neither is configurable:

- **The remote must be `https`, `ssh`, or SCP-style `git@host:path`.** A plain `http://` URL is
  rejected before git runs (`Assert-SecureGitUrl`). The configuration executes as trusted code in
  the job's own security context, so a tamperable transport is a code execution path into the
  agent.
- **The clone is cleaned up.** It lands in an owner-only directory that is removed when the run
  ends, even if the run throws. `-KeepTemporaryDirectory` opts out while debugging.

Pin what you fetch with `-ConfigurationRevision`, especially on an ephemeral agent where
"whatever the tracked branch was at that moment" is otherwise unrecoverable after the job exits:

```powershell
# Exact pin: the clone's resolved HEAD is verified against the SHA, and the run fails on a mismatch.
Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath $repoUrl `
                 -ConfigurationRevision '8f0a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b' `
                 -Engine DscV3
```

The resolved `HEAD` SHA is written to the information stream on every clone, so the job log
records the commit that ran even when no revision was pinned.

### Workload-identity federation (recommended — no stored PAT)

A Personal Access Token is a long-lived secret you have to store, rotate and protect.
**Workload-identity federation** replaces it with a short-lived token the platform mints for the
running job from its own trusted identity — nothing long-lived is stored in the pipeline.

- **Azure DevOps** — configure a
  [workload identity federation service connection](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure)
  for the pipeline. The agent exposes the job's OAuth token as `$(System.AccessToken)` (enable
  *"Allow scripts to access the OAuth token"* on the job), and you pass it straight to
  `-JITToken`:

  ```yaml
  steps:
    - pwsh: |
        Import-Module DSC.PipelineRunner.Akkodis
        Invoke-DscPipelineRunner -AzureDevopsOrganizationName 'Contoso' `
                                 -exportConfigDir .\out `
                                 -ConfigurationSourcePath "$(ConfigRepoUrl)" `
                                 -JITToken "$(System.AccessToken)" `
                                 -Engine DscV3
  ```

- **GitHub Actions** — the job's `GITHUB_TOKEN` (or an OIDC token exchanged for a short-lived
  credential via `id-token: write`) is the federated credential. Set it as
  `$env:SYSTEM_ACCESSTOKEN` so the `Source`/`Git` action's automatic fallback picks it up:

  ```yaml
  permissions:
    contents: read
    id-token: write
  steps:
    - shell: pwsh
      env:
        SYSTEM_ACCESSTOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: |
        Import-Module DSC.PipelineRunner.Akkodis
        $dir = Invoke-Action -Hook Source -Name Git -Context @{
          Url = '${{ github.server_url }}/${{ github.repository }}'
        }
        Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath $dir -Engine DscV3
  ```

Because these tokens are minted per-job and expire quickly, a leak is far less damaging than a
leaked PAT — and there is no secret to rotate. Prefer federation over a stored PAT wherever the
platform supports it.

---

## Continuous validation

There is no dedicated "DSC v3 on Linux" CI workflow in this repo's `.github/workflows/` at the
time of writing — unlike upstream, which runs a bootstrap-and-smoke-test job on every push. If
you add one, `Test-DscExecutableAvailable` and `Actions/Engine/DscV3.ps1` are the two pieces to
exercise against a real `dsc` binary on a clean Ubuntu runner.

## See also

- [docs/dsc-v3.md](dsc-v3.md) — converting a compiled configuration into a DSC v3 configuration
  document, and the `Engine` selection mechanics.
- [WikiSource/Engines.md](../WikiSource/Engines.md) — the full engine reference.
- [WikiSource/Remote-Targets-and-Credentials.md](../WikiSource/Remote-Targets-and-Credentials.md)
  — running `DscV3` against a remote target rather than the local agent.
