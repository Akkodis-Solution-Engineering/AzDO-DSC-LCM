# Scheduled Enforcement and Execution Overrides

Two more extensions this fork has that the upstream project does not: a **time-windowed**
enforcement mode declared once for the whole run, and a **per-resource** override of that mode.
Together they let a node apply changes only inside a declared maintenance window while still
reporting drift the rest of the time, and let one resource opt out of whatever mode the run is
otherwise using.

## `PipelineConfigurationMode`

A top-level block in the configuration's `Datum.yml`, read and validated by
`Test-DatumConfiguration` alongside `PipelineRunnerSettings` (see
[PipelineRunnerSettings](PipelineRunnerSettings)) and resolved once per run by
`Get-PipelineRunnerConfigurationMode`.

```yaml
PipelineConfigurationMode:
  # ApplyOnly, Audit, Enforce, or Scheduled.
  ConfigurationMode: Scheduled
  ChangeWindows:
    - StartTime: '20:00'          # Audit every night — UTC.
      EndTime: '23:59'
      ConfigurationMode: Audit
    - StartTime: '00:00'          # Enforce only during the Tuesday/Wednesday/Thursday
      EndTime: '02:00'            # maintenance window.
      ConfigurationMode: Enforce
      DaysOfWeek:                 # Optional. Omit to apply the window every day.
        - Tuesday
        - Wednesday
        - Thursday
```

### Static modes

`ApplyOnly`, `Audit` and `Enforce` need no `ChangeWindows` block; the mode is fixed for the
whole run. `ChangeWindows` is still required by `Test-DatumConfiguration`'s schema check, but is
only interpreted when `ConfigurationMode` is `Scheduled`.

### `Scheduled`

`Get-PipelineRunnerConfigurationMode` evaluates `ChangeWindows` **in declaration order**, against
the current UTC time and day of week:

1. A window matches when the current UTC time falls in `[StartTime, EndTime)` **and**, if the
   window declares `DaysOfWeek`, the current UTC day is in that list. Omitting `DaysOfWeek`
   matches every day.
2. The **first** matching window wins. Later matching windows are ignored, and a warning is
   emitted if more than one window would otherwise match — overlapping windows are a
   configuration smell worth fixing, not a silent pick.
3. **No match falls back to `Audit`.** A `Scheduled` configuration with gaps between its windows
   is safe by construction: outside every declared window, the run only reports drift, it never
   applies changes.

Both `StartTime` and `EndTime` are `HH:mm` 24-hour strings, always interpreted as **UTC** —
convert your local maintenance window before writing it. `Test-DatumConfiguration` rejects a
`ChangeWindow` whose `StartTime`/`EndTime` do not parse in that format, an unrecognised
`ConfigurationMode` value inside a window (`Scheduled` itself is not valid *inside* a window —
only `ApplyOnly`, `Audit` and `Enforce` are), or an unrecognised `DaysOfWeek` entry.

A window whose `EndTime` is numerically before its `StartTime` is **not** treated as wrapping
past midnight — write two windows if a maintenance period spans midnight, as the example above
does with its `00:00`–`02:00` window.

### Where the resolved mode goes

The mode `Get-PipelineRunnerConfigurationMode` resolves for this run — `ApplyOnly`, `Audit` or
`Enforce` — is what the rest of the pipeline reads as the run's effective mode. It is resolved
**once per run**, not once per file or per resource, so a run that straddles a window boundary
uses whichever mode was in effect when it started.

## `executionMethodOverride`

A resource-level key, read from `source/Enum/000.ExecutionMethod.ps1`'s `[ExecutionMethod]` enum
(`None`, `Test`, `Set`), that lets one resource ignore the run's overall mode:

```yaml
resources:

  - name: One-Way Migration Flag
    type: PSDscResources/Registry
    executionMethodOverride: Set
    properties:
      Key: HKLM:\Software\Contoso
      ValueName: MigrationApplied
      ValueData: '1'
      Ensure: Present
```

| Value | Effect |
| --- | --- |
| `None` (default) | No override. The resource follows whatever mode the run resolved — `Test` or `Set` (from `-Mode`, itself potentially derived from `PipelineConfigurationMode`). |
| `Test` | This resource always evaluates in `Test`-only mode: drift is reported, nothing is changed, even when the run overall is applying changes. |
| `Set` | This resource always applies changes, even when the run overall is only testing — for example, during an `Audit` window of a `Scheduled` configuration. |

An invalid value throws at compile time, naming the resource and the permitted set:

```
[DSC_Resource] Invalid executionMethodOverride value: <detail>. Valid values are: 'Test', 'Set', 'None'.
```

`Start-DscRunner` reads it immediately before the `Test()` call: if the value is present and not
`None`, it becomes this resource's effective execution mode for the rest of the resource's
lifecycle (notify-forced-refresh, the `Set()` decision, reboot handling) — everything downstream
behaves exactly as if the whole run were in that mode, for this one resource only.

### Why this exists

`PipelineConfigurationMode: Scheduled` is a blunt instrument by design — it is a maintenance
window for the *whole node*. `executionMethodOverride` is the escape hatch for the resource that
must not wait for the window: a one-time migration flag, a break-glass credential rotation, or a
resource whose drift is expected and must never gate the build (`Test` override on a resource
that is known to fluctuate, so its drift never turns an `Enforce` run's exit code red via
`-FailOnError`).

Combine the two deliberately, not by accident: a resource carrying `executionMethodOverride: Set`
inside a configuration whose `PipelineConfigurationMode` is `Scheduled` with an `Audit`-only
window will still apply changes during that window. Document why on the resource, since the
behaviour is the opposite of what the surrounding `Audit` window implies for every other
resource in the file.

## Related pages

- [PipelineRunnerSettings](PipelineRunnerSettings) — the sibling settings block for engine
  selection, execution scripts, reboot policy and the default target.
- [Resource Properties](Resource-Properties) — the full per-resource key set.
- [Reporting and Exit Codes](Reporting-and-Exit-Codes) — how a resource's effective mode (base or
  overridden) determines whether drift becomes `FAIL`.
