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

How values combine (`Join-Properties`, with the stub's properties as the source):

- A key only one side sets is kept.
- A scalar both set takes the **stub's** value. Stubs are applied in declaration order, so a
  later stub overrides an earlier one.
- Nested hashtables are merged key by key with the same rules.
- Lists (for example an `AzDoGitPermission` `Permissions` list) are combined, stub entries
  first, with duplicates removed. Hashtable entries are compared regardless of key order.

```yaml
- name: Project
  type: AzureDevOpsDscNative/AzDoProject
  mergable: true
  properties:
    projectName: Magenta
    visibility: private

- name: Project Visibility Override
  type: AzureDevOpsDscNative/AzDoProject
  merge_with: AzureDevOpsDscNative/AzDoProject/Project
  properties:
    visibility: public      # the compiled Project resource runs with visibility: public
```

Three things are enforced, each failing the file's run before any resource is evaluated:

- **The target must exist in the same compiled file.** Stub merging is intra-file, exactly like
  `dependsOn`, `notify` and `using()`:

  ```
  [Merge-StubResources] Resource 'AzureDevOpsDscNative/AzDoProject/Project' named by merge_with was not found in this configuration file.
  ```

- **The target must be unique.** A `merge_with` identity matching more than one resource fails,
  naming the count.
- **The target must opt in with `mergable: true`**, so a resource author explicitly declares
  that being merged into is safe:

  ```
  [Merge-StubResources] Resource 'AzureDevOpsDscNative/AzDoProject/Project' is not a stub target. Add 'mergable: true' to it to allow merge_with.
  ```

Stubs declared inside a composite file are merged within that file when the composite is
expanded.

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
    properties:
      RepositoryName: $(variables('ProjectRepositoryName'))
```

`CompositeResources/ConfigurationRepository.yml`, resolved from the `CompositeResources`
directory at the configuration root:

```yaml
parameters:
  RepositoryName:
    defaultValue: Configuration

variables: {}

resources:

  - name: Configuration Git Repository
    type: AzureDevOpsDscNative/AzDoGitRepository
    dependsOn:
      - AzureDevOpsDscNative/AzDoProject/Project
    properties:
      ProjectName: $(variables('ProjectName'))
      RepositoryName: $(parameters('RepositoryName'))
      Ensure: Present
```

`RepositoryName` comes from the composite node's `properties`, which are passed in as the
composite's parameters and override its `defaultValue`. `ProjectName` is not declared in the
composite, so it resolves from the file that references it.

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

### Scope

Every resource spliced in from a composite carries a scope layer built from that composite:

- **Parameters**: the composite file's `parameters` defaults, overridden by the composite
  node's `properties`. Property values are resolved in the referencing file's scope, so
  `$(variables('ProjectRepositoryName'))` on the node reads the parent's variable.
- **Variables**: the composite file's `variables` block.

While one of those resources runs, its layers are applied over the referencing file's own
parameters and variables (outermost composite first, so a nested composite's values win), and
they are removed again before the next resource. As a result:

- Two composites, or a composite and the file that references it, can declare the same name
  without clobbering each other.
- Anything a composite does not declare still resolves from the referencing file.
- A composite's variables are also visible to its resources' `preExecutionScript` /
  `postExecutionScript` as `$Name`, but are not exported as environment variables.

### Where composites fit in the pipeline

```
Merge-StubResources        → runs first on the referencing file, so a stub there cannot target
                             a composite's inner resources (stubs inside the composite file are
                             merged when it is expanded)
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
