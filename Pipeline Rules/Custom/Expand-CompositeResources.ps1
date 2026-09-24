<#
.SYNOPSIS
Splices a DSCCompositeResource's linked configuration's inner resources into the pipeline in
place of the composite node.

.DESCRIPTION
[DSCCompositeResource] (source/Classes/004.DSCCompositeResource.ps1) loads its linked
composite .yml file into a [DSCConfigurationFile] at construction time. This rule walks the
resource list, and for every [DSCCompositeResource] found, replaces it with its linked
configuration's own (recursively expanded) resources. There is no equivalent in
Dsc.PipelineRunner, which has no concept of a composite resource.

Scope: each inner resource is tagged with a scope layer (see DSC_Resource.compositeScope)
holding the composite's own parameters and variables:

- Parameters are the composite file's parameter defaults, overridden by the composite node's
  own `properties` - so `properties: { SiteName: Contoso }` on the node is read inside the
  composite as `$(parameters('SiteName'))`.
- Variables are the composite file's `variables` block.

Start-DscRunner applies the layers over the file's own scope only while that inner resource
runs, so two composites (or a composite and its parent file) can declare the same name
without clobbering each other. Anything the composite does not declare still resolves from the
parent file's scope.

Stubs declared inside the composite file are merged into their targets inside that file
before its resources are spliced in.

Must run after Merge-StubResources and before ConvertTo-PipelineTask /
Expand-NotifyDependsOn / Sort-DependsOn (composites must be fully expanded before dependency
ordering sees the real resource list).

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

    if ($null -eq $resource.resource.resources -or @($resource.resource.resources).Count -eq 0) {
        Write-Verbose "[Expand-CompositeResources] Composite resource '$($resource.getFullResourceName())' has no inner resources; nothing to splice in."
        continue
    }

    # Build this composite's scope layer: its parameter defaults, overridden by the values the
    # composite node passes in through its properties, plus its own variables.
    $layerParameters = @{}
    if ($resource.resource.parameters) {
        $defaults = GetDefaultValues -Source $resource.resource.parameters
        foreach ($key in $defaults.Keys) { $layerParameters[$key] = $defaults[$key] }
    }
    if ($resource.properties) {
        foreach ($key in $resource.properties.Keys) { $layerParameters[$key] = $resource.properties[$key] }
    }
    $layerVariables = @{}
    if ($resource.resource.variables) {
        foreach ($key in $resource.resource.variables.Keys) { $layerVariables[$key] = $resource.resource.variables[$key] }
    }
    $layer = @{
        Composite  = $resource.getFullResourceName()
        Parameters = $layerParameters
        Variables  = $layerVariables
    }

    # Merge the composite file's own stubs, then recursively expand nested composites.
    $innerResources = @(Invoke-CustomTask -Tasks $resource.resource.resources -CustomTaskName 'Merge-StubResources')
    if ($innerResources.Count -gt 0) {
        $innerResources = @(Invoke-CustomTask -Tasks $innerResources -CustomTaskName 'Expand-CompositeResources')
    }

    foreach ($inner in $innerResources) {
        # Outermost composite first, so a nested composite's own values win.
        $inner.compositeScope = @($layer) + @($inner.compositeScope)
        $null = $expanded.Add($inner)
    }
}

return $expanded
