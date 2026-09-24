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
# ProjectPolicies/ProjectGroups.yml
resources:

  - name: CON Readers
    type: AzureDevOpsDscNative/AzDoProjectGroup
    mergable: true
    properties:
      ProjectName: $(variables('ProjectName'))
      GroupName: $(variables('ProjectGroups_Role_CONReaders'))

# Projects/Present/Magenta.yml - a more specific Datum layer. After Datum's merge both entries
# sit in the same compiled file, and the stub is folded into 'CON Readers' at evaluation time.
resources:

  - name: Magenta Readers Group
    type: AzureDevOpsDscNative/AzDoProjectGroup
    merge_with: AzureDevOpsDscNative/AzDoProjectGroup/CON Readers
    properties:
      Ensure: Present
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

`Merge-StubResources` groups every stub by its `merge_with` value, locates the resource in the
same compiled file whose `Module/ResourceName/Instance` identity matches, and merges each stub's
`properties` onto the target's `properties` with `Join-Properties`. The stub itself is then
dropped from the resource list.

The merge is **additive**:

- A key the target does not set is added from the stub.
- A key both set keeps the **target's** value — a stub cannot override a property the target
  already declares. To change an existing value, override the target itself at a more specific
  Datum layer using the same `name` (see above).
- Merging array-of-hashtable properties (for example an `AzDoGitPermission` `Permissions`
  list) is currently broken: `Join-Properties` calls a `Sort-Hashtable` helper that does not
  exist, and the merged array comes back empty. Do not point a stub at an array property until
  that is fixed.

What is and is not enforced today:

- **A missing target is a warning, not a failure.** A `merge_with` naming a resource that is not
  in the same compiled file writes
  `[Merge-StubResources] Resource not found: <merge_with>` and the stub is discarded. Stub
  merging is intra-file, exactly like `dependsOn`, `notify` and `using()`.
- **`mergable: true` is not currently checked.** Mark every intended target with
  `mergable: true` anyway — it documents intent, and the `[DSCStub]` class carries a `merge()`
  method that rejects unmarked targets, but `Merge-StubResources` performs its own merge and
  does not call it.

## Composite resources

A composite resource's `type` is `composite/<name>`, where `<name>` is the base filename (no
extension) of another configuration file living alongside the one that references it. Unlike an
ordinary resource, a composite node contributes **no directly-executable DSC resource of its
own** — the whole point is that it stands in for the composite file's own `resources:` list.

```yaml
# Projects/Present/Magenta.yml
resources:

  - name: Configuration Repository
    type: composite/ConfigurationRepository
```

`CompositeResources/ConfigurationRepository.yml`, resolved from the `CompositeResources`
directory at the configuration root:

```yaml
parameters: {}

variables: {}

resources:

  - name: Configuration Git Repository
    type: AzureDevOpsDscNative/AzDoGitRepository
    dependsOn:
      - AzureDevOpsDscNative/AzDoProject/Project
    properties:
      ProjectName: $(variables('ProjectName'))
      RepositoryName: $(variables('ProjectRepositoryName'))
      Ensure: Present
```

`ProjectName` and `ProjectRepositoryName` are not declared in the composite. They resolve
because the composite shares the run's variable scope, and the node file that references it
(together with `ProjectPolicies/Project.yml`) declares them. A `properties:` block on the
composite node is **not** passed into the composite — it is ignored.

### What actually happens

`[DSCCompositeResource]` (constructed when a resource's `type` matches `^composite[\\/](?<resource>.+$)`)
loads the linked `.yml` as a full `[DSCConfigurationFile]` at parse time — this is what fails
fast, before any expansion, if the file is missing:

```
[DSCCompositeResource] Error. The composite resource cannot be found. Please check that the
file is named correctly and try again. FilePath: <path>/CompositeResources/ConfigurationRepository.yml
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
will clobber each other — whichever is expanded last wins. Because the composite node's own
`properties` are not passed in, parameterize a composite through variables or parameters
declared by the file that references it, and give composite-level defaults names that will not
collide.

### Where composites fit in the pipeline

```
Merge-StubResources        → runs first, so a stub cannot target a composite's inner resources
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
