# Composite and Stub Resources

Two resource shapes exist in this fork that have no equivalent in the upstream project: a
**stub (partial) resource**, which merges its properties into another resource declared at a
different Datum layer, and a **composite resource**, which expands into the resources of a
whole other configuration file. Both are resolved before `dependsOn`/`notify` ordering, so by
the time `Sort-DependsOn` runs, only ordinary DSC resources remain.

```
Merge-StubResources        → fold every stub's properties into its merge_with target
Expand-CompositeResources  → replace every composite node with its linked file's resources
Expand-NotifyDependsOn
Sort-DependsOn
```

Both are `Pipeline Rules/Custom/` tasks (see [Pipeline Rules](Pipeline-Rules)), and both run
**before** the pre-parse validation rules, so `Test-ResourcesForIncorrectProperties` sees the
fully-merged, fully-expanded resource list — never a stub or a composite node directly.

## Stub (partial) resources

A stub resource is declared with `merge_with` instead of a normal resource body. It carries no
`dependsOn`, `notify`, `target` or condition keys of its own — only `name`, `type`,
`properties` and `merge_with` are read from it.

```yaml
resources:

  - name: Project
    type: AzureDevOpsDscNative/AzDoProject
    mergable: true
    properties:
      projectName: Magenta
      visibility: private

  # Declared at a more specific Datum layer (e.g. a node file), merged into the
  # 'Project' resource above at compile-evaluation time.
  - name: Project Visibility Override
    type: AzureDevOpsDscNative/AzDoProject
    merge_with: AzureDevOpsDscNative/AzDoProject/Project
    properties:
      visibility: public
```

`merge_with` names the **target's full identity** — `Module/ResourceName/Instance`, the same
shape `dependsOn` and `notify` use, not the bare instance name `reference()` uses.

### Why not just override the property directly?

Because Datum's `resources` merge is keyed on `name`, two layers declaring a resource with the
**same `name`** already merge automatically — that is the ordinary override pattern documented
on [Configuration Repository Layout](Configuration-Repository-Layout). A stub resource is for
the case where the overriding layer wants to contribute properties under a **different `name`**
— for example, a cross-cutting policy layer that adds one property to many different resources
without knowing each target's exact `name` in advance, or a layer that wants its contribution to
show up as a distinct entry in the compiled YAML for readability/auditing, merged only at
evaluation time rather than at Datum's own merge time.

### The merge itself

`Merge-StubResources` groups every stub by its `merge_with` value, locates the one resource in
the file whose `Module/ResourceName/Instance` identity matches, and merges each stub's
`properties` onto the target's `properties` with `Join-Properties` — later stubs win over
earlier ones for a given property.

Two things are enforced, both as hard failures:

- **The target must exist in the same compiled file.** A `merge_with` naming a resource that is
  not present — including one that exists only in a different compiled file — fails the run.
  Stub merging is intra-file, exactly like `dependsOn`, `notify` and `using()`.
- **The target must opt in with `mergable: true`.** A stub whose target does not carry
  `mergable: true` is rejected:

  ```
  [DSCStub] Error: Resource 'AzureDevOpsDscNative/AzDoProject/Project' does not contain a
  'mergable' property.
  ```

  This is deliberate: a resource author has to explicitly declare that being merged into is
  safe, rather than any resource in the configuration silently becoming a merge target.

A `merge_with` naming a resource that genuinely does not exist anywhere in the file throws too:

```
[DSCStub] Error: Resource 'AzureDevOpsDscNative/AzDoProject/Project' not found in provided DSC resources.
```

and a `merge_with` value that matches more than one resource — which should not be possible
given `name` uniqueness, but is guarded anyway — throws naming the count.

## Composite resources

A composite resource's `type` is `composite/<name>`, where `<name>` is the base filename (no
extension) of another configuration file living alongside the one that references it. Unlike an
ordinary resource, a composite node contributes **no directly-executable DSC resource of its
own** — the whole point is that it stands in for the composite file's own `resources:` list.

```yaml
resources:

  - name: Web Tier
    type: composite/WebTier
    properties:
      SiteName: Contoso
```

`WebTier.yml`, resolved relative to the composite directory:

```yaml
parameters:
  SiteName: {}

variables:
  DeployRoot: C:\inetpub

resources:

  - name: Site Directory
    type: PSDscResources/File
    properties:
      DestinationPath: $(concat (variables 'DeployRoot') '\' (parameters 'SiteName'))
      Type: Directory
      Ensure: Present

  - name: Web Feature
    type: PSDscResources/WindowsFeature
    properties:
      Name: Web-Server
      Ensure: Present
```

### What actually happens

`[DSCCompositeResource]` (constructed when a resource's `type` matches `^composite[\\/](?<resource>.+$)`)
loads the linked `.yml` as a full `[DSCConfigurationFile]` at parse time — this is what fails
fast, before any expansion, if the file is missing:

```
[DSCCompositeResource] Error. The composite resource cannot be found. Please check that the
file is named correctly and try again. FilePath: <path>\WebTier.yml
```

`Expand-CompositeResources` then walks the resource list and, for every composite node it finds,
**replaces it in place** with the linked file's own resources — recursively, so a composite that
itself references another composite is expanded fully before `Sort-DependsOn` ever runs. A
composite with no inner `resources:` at all is a no-op: it contributes nothing and is silently
dropped.

### Scope: shared, not isolated

Before splicing in the inner resources, the composite's own `parameters` and `variables` blocks
(if it declares any as file-level defaults) are folded into the run's shared `$parameters` /
`$variables` scope — the same module-scope hashtables an ordinary top-level configuration file
populates. This is what lets the inner resources' `$(parameters(...))` and `$(variables(...))`
calls resolve normally.

The consequence is that **composites do not get their own isolated scope**. Two composites (or a
composite and the file that references it) that declare a parameter or variable of the same name
will clobber each other — whichever is expanded last wins. Parameterize a composite through its
own resource's `properties` block (read inside the composite via `$(parameters(...))` once the
composite's own `parameters:` block names them) rather than relying on name collisions not
happening.

### Where composites fit in the pipeline

```
Merge-StubResources        → composites cannot be stub targets or stubs themselves
Expand-CompositeResources  → runs after stubs, before dependency ordering
Expand-NotifyDependsOn
Sort-DependsOn
```

Because expansion happens before `Expand-NotifyDependsOn` and `Sort-DependsOn`, a composite's
inner resources participate in **this file's** `dependsOn`/`notify` graph exactly as if they had
been written inline — but a composite node itself cannot be the target of a `dependsOn` or
`notify`, since by the time those rules run it no longer exists as a distinct resource. Point a
dependency at one of the composite's *inner* resource identities instead.

## Related pages

- [Resource Properties](Resource-Properties) — the full key set for an ordinary resource, plus
  `executionMethodOverride`.
- [Pipeline Rules](Pipeline-Rules) — how `Merge-StubResources` and `Expand-CompositeResources`
  fit among the other custom tasks and pre-parse rules.
- [Scheduled Enforcement and Execution Overrides](Scheduled-Enforcement) — the other
  repo-specific extension, for time-windowed and per-resource enforcement.
