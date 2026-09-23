# DSC v3 support

`DSC.PipelineRunner.Akkodis` (ported from `Dsc.PipelineRunner`) can drive Microsoft's
[DSC v3](https://learn.microsoft.com/powershell/dsc/) engine (`dsc` / `dsc.exe`), the
cross-platform successor to the Windows-first `Invoke-DscResource` (DSC v2) path. Engine
selection itself — how `-Engine`, `PipelineRunnerSettings.Engine`/`DSCResourceVersion` and
`Auto` detection interact — is covered in full in
[WikiSource/Engines.md](../WikiSource/Engines.md); this page covers the part that trips people
up once you're on DSC v3: making sure a compiled Datum configuration is actually something
`dsc.exe` will accept.

Both entry points — the provider-agnostic `Invoke-DscRunner` and the Azure-DevOps-flavored
`Invoke-DscPipelineRunner` — accept `-Engine DscV3` (or `-Engine Auto` to detect a `dsc` on
`PATH`); `Invoke-DscPipelineRunner` simply resolves Azure DevOps authentication first and then
delegates to `Invoke-DscRunner`.

## Selecting the engine

The execution engine is a pluggable action (`Actions/Engine/<Engine>.ps1`):

| Engine  | Backing tool           | Platforms             |
| ------- | ----------------------- | ---------------------- |
| `DscV2` | `Invoke-DscResource`    | Windows (PowerShell)   |
| `DscV3` | `dsc` / `dsc.exe`       | Windows, Linux, macOS  |

```powershell
Invoke-DscRunner -exportConfigDir .\out -ConfigurationSourcePath .\config -Engine DscV3
```

## Compiled configuration vs. a DSC v3 configuration document

The runner's compiled Datum output is a **runner-specific** shape — a list of resources plus
pipeline-only keys the runner interprets itself:

```yaml
resources:
  - type: Microsoft.Windows/Registry     # namespace/name
    name: SetKey
    properties: { keyPath: '...', valueName: '...', valueData: { String: 'x' } }
    preCondition: "1 -eq 1"                # pipeline-only
    postExecutionScript: "..."             # pipeline-only
    dependsOn: [ ... ]                     # pipeline-only (runner orders execution)
    notify: [ ... ]                        # pipeline-only
parameters: { ... }                      # pipeline-only
variables:  { ... }                      # pipeline-only
```

`Start-DscRunner` consumes this one resource at a time: it sorts by `dependsOn` (after folding
`notify` into implicit `dependsOn` entries), evaluates `preCondition`, resolves `properties`
(parameter tokens first, then variables and calculated properties), and calls the selected
engine per resource. The `DscV3` engine (`Actions/Engine/DscV3.ps1`) turns each resource into
`dsc resource test|set|get --resource <type> --input <json>`.

A **DSC v3 configuration document** — what `dsc config get|test|set` consumes — is a different,
schema-governed shape. It carries a top-level `$schema` and resources limited to `name`, `type`
and `properties`; it has no concept of the runner's `preCondition`, `postExecutionScript`,
`notify`, `variables`, or the runner's `parameters`:

```yaml
$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json
resources:
  - name: SetKey
    type: Microsoft.Windows/Registry
    properties: { keyPath: '...', valueName: '...', valueData: { String: 'x' } }
```

## Making a compiled configuration DSC v3-compliant

Use the exported **`ConvertTo-DscV3ConfigurationDocument`** function
(`source/Public/ConvertTo-DscV3ConfigurationDocument.ps1`) to turn compiled resources into a
document that `dsc.exe` accepts. It:

- stamps the DSC v3 `$schema`,
- keeps only `name`, `type` and `properties`, dropping every pipeline-only key,
- validates that each resource has a non-empty `name` and a `type` shaped like a DSC v3
  identifier (`namespace/name`, e.g. `Microsoft.Windows/Registry`), via `Test-DscV3ResourceType`,
- optionally verifies each `type` actually exists on the box when you pass the set from
  `dsc resource list` via `-AvailableResourceType`,
- aggregates all problems and throws a single itemized error.

```powershell
# From an in-memory compiled configuration (properties already resolved):
$types = (dsc resource list --output-format json | ConvertFrom-Json).type
$doc   = ConvertTo-DscV3ConfigurationDocument -Resource $compiled.resources -AvailableResourceType $types

# Hand it to dsc.exe (write to a file and use --file; the config subcommands read a path):
$doc | ConvertTo-Json -Depth 32 | Set-Content ./config.dsc.json -Encoding utf8
dsc config get --file ./config.dsc.json
```

Two things the runner keeps as its own responsibility, by design (see
[WikiSource/Engines.md § "`dsc config` is not used"](../WikiSource/Engines.md)):

- **Ordering.** `dependsOn` is not carried into the document — the runner has already ordered
  the resources (`Sort-DependsOn`, after `notify` has been folded into it). Pass resources in
  already the order you want them evaluated.
- **Resolution.** `properties` are emitted verbatim. Run the runner's own two-pass
  resolution — `Expand-HashTable` after `Expand-Parameters` — before converting if you want a
  fully-resolved document; parameter tokens first, then variables and calculated properties.

`ConvertTo-DscV3ConfigurationDocument` is an exported public helper with **no internal caller**:
`Start-DscRunner` never calls `dsc config` itself, only `dsc resource <verb>` once per resource,
because the runner makes decisions *between* resources (a `preCondition`, a
`postExecutionScript`, a notify-forced refresh, a reboot policy) that a whole-document
`dsc config` apply would surrender. The function exists for a caller that wants a v3
configuration document for some other purpose — CI verification, a one-off export, tooling
outside the runner's own loop.

### Resource types must be DSC v3 types

The most common cause of a "compliant-looking but unusable" configuration is a resource `type`
that is a DSC **v2** module/resource pair (for example `PSDscResources/Service`) rather than a
DSC **v3** resource type. Both are `namespace/name` shaped, so a structural check cannot tell
them apart — only `dsc resource list` can. That is why `ConvertTo-DscV3ConfigurationDocument`
accepts `-AvailableResourceType`, and why `Actions/Engine/DscV3.ps1` surfaces a clear error when
a type is not a DSC v3 identifier instead of leaving you with an opaque non-zero exit from
`dsc.exe`.

## Configuration functions (planned, not yet implemented)

DSC v3 configuration documents have their own native function language
(`[functionName(arg1, arg2)]` — `envvar()`, `resourceId()`, `concat()`, its own document-scoped
`parameters()`/`variables()`, and more), separate from the runner's own `$(...)` function
surface described in `Assert-SafeConditionExpression.ps1`, `source/Private/Runner/*.ps1` and
[WikiSource/Function-Language.md](../WikiSource/Function-Language.md). Handling that syntax, and
the whole-document (`dsc config get|test|set`) apply path it would require, is not implemented
in this repo (nor was it upstream) — see
[`docs/dsc-v3-config-functions.md`](dsc-v3-config-functions.md) for the design plan.

## See also

- [WikiSource/Engines.md](../WikiSource/Engines.md) — the full engine-selection and
  engine-contract reference, including remote targets and reboot signalling for `DscV3`.
- [docs/hosted-agent-dsc-v3.md](hosted-agent-dsc-v3.md) — running the `DscV3` engine on a hosted
  Linux agent.
