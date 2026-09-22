<#
.SYNOPSIS
Splices a DSCCompositeResource's linked configuration's inner resources into the pipeline in
place of the composite node.

.DESCRIPTION
[DSCCompositeResource] (source/Classes/004.DSCCompositeResource.ps1) loads its linked
composite .yml file into a [DSCConfigurationFile] at construction time, but nothing previously
expanded that file's own resources into the execution list - the composite node itself carried
no directly-executable DSC resource, so it was silently a no-op once it reached Start-DscRunner.
This rule is new code (there is no equivalent in Dsc.PipelineRunner, which has no concept of a
composite resource) that closes that gap: it walks the resource list, and for every
[DSCCompositeResource] found, replaces it with its linked configuration's own (recursively
expanded) resources.

Scope note: a composite's own `parameters`/`variables` block is folded into the shared
$parameters/$variables scope (the same module-scope hashtables GetDefaultValues/SetVariables
populate for the top-level configuration file) so its inner resources' <params=...> tokens and
variable expansion resolve normally. This gives every composite a shared, not an isolated,
scope: two composites (or a composite and its parent file) that declare a parameter/variable of
the same name will clobber each other here. Configurations in this repo parameterize composites
through their own `properties` block rather than colliding names, so this is judged an
acceptable simplification rather than building full per-composite scope isolation.

Must run after Merge-StubResources (so a stub already merged into its target does not need
special-casing here) and before ConvertTo-PipelineTask / Expand-NotifyDependsOn / Sort-DependsOn
(composites must be fully expanded before dependency ordering sees the real resource list).

.PARAMETER PipelineResources
An array of pipeline resources (DSC_Resource / DSCStub / DSCCompositeResource instances)
produced by Merge-StubResources.

.OUTPUTS
System.Collections.ArrayList
The same resources, with every DSCCompositeResource replaced by its expanded inner resources.
#>
[CmdletBinding()]
[OutputType([System.Collections.ArrayList])]
param(
    [Object[]]$PipelineResources
)

$expanded = [System.Collections.ArrayList]::new()

foreach ($resource in $PipelineResources) {

    if ($resource -isnot [DSCCompositeResource]) {
        $null = $expanded.Add($resource)
        continue
    }

    Write-Verbose "[Expand-CompositeResources] Expanding composite resource: $($resource.getFullResourceName())"

    # Fold the composite's own declared defaults/variables into the shared scope (see
    # scope note above) before its inner resources are handed back - their property
    # expansion later reads $parameters/$variables by name, not from this rule's return
    # value, so this must happen as a side effect here.
    if ($resource.resource.parameters) {
        $compositeDefaults = GetDefaultValues -Source $resource.resource.parameters
        SetVariables -Source $compositeDefaults -Target $parameters
    }
    if ($resource.resource.variables) {
        SetVariables -Source $resource.resource.variables -Target $variables
    }

    if ($null -eq $resource.resource.resources -or @($resource.resource.resources).Count -eq 0) {
        Write-Verbose "[Expand-CompositeResources] Composite resource '$($resource.getFullResourceName())' has no inner resources; nothing to splice in."
        continue
    }

    # Recursively expand in case a composite itself links to another composite.
    $innerResources = Invoke-CustomTask -Tasks $resource.resource.resources -CustomTaskName 'Expand-CompositeResources'

    foreach ($inner in $innerResources) {
        $null = $expanded.Add($inner)
    }
}

return $expanded
