[CmdletBinding()]
[OutputType([System.Collections.ArrayList])]
param(
    [Object[]]$PipelineResources
)

# Find any Stub Resources
$StubResources, $Resources = $PipelineResources.Where($_ -is [DSCStub], 'Split')

# If there are no stub resources, return the origional Object
if ([Array]$Stub.Resources.Count -eq 0) {
    return $PipelineResources
}

# Now there are stub resources we need to merge these resources

# Group the stub resources by the 'MergeWith' property
$GroupResources = $StubResources | Group-Object -Property MergeWith

ForEach ($GroupResource in $GroupResources) {
    # Find the resource that the stub resource is to be merged with
    $Resource = $Resources | Where-Object { $_.Name -eq $GroupResource.Name }

    # If the resource is not found, write a warning and continue
    if ($null -eq $Resource) {
        Write-Warning "[Merge-StubResources] Resource not found: $($GroupResource.Name)"
        continue
    }

    # Merge the stub resource properties with resource properties.
    $GroupResource.Group | ForEach-Object {
        $Resource.properties = Join-Properties -source $Resource.properties -merge $_.properties
    }

}

return $Resources