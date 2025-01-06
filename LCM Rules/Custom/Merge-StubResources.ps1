<#
.SYNOPSIS
Merges stub resources with their corresponding target resources from the pipeline input.

.DESCRIPTION
The `Merge-StubResources` cmdlet identifies stub resources from the provided pipeline input and merges their properties with the corresponding target resources. If no stub resources are found, the original pipeline resources are returned. The merging process groups stub resources by the 'MergeWith' property and combines their properties with the target resources.

.PARAMETER PipelineResources
An array of objects representing the pipeline resources, which may include stub resources.

.OUTPUTS
System.Collections.ArrayList
Returns an array list of resources with merged properties if stub resources are found; otherwise, returns the original pipeline resources.

.EXAMPLE
PS> $resources = Get-PipelineResources
PS> $mergedResources = Merge-StubResources -PipelineResources $resources
Merges any stub resources in the pipeline resources with their corresponding target resources and returns the updated resources.

.NOTES
This cmdlet is designed to work with DSC (Desired State Configuration) stub resources, identified by the [DSCStub] type. The merging process relies on the 'MergeWith' property to determine which resources should be combined.

#>
[CmdletBinding()]
[OutputType([System.Collections.ArrayList])]
param(
    [Object[]]$PipelineResources
)

# Find any Stub Resources
Write-Verbose "[Merge-StubResources] Identifying stub resources from pipeline input."
$StubResources, $Resources = $PipelineResources.Where({$_ -is [DSCStub]}, 'Split')

# If there are no stub resources, return the original Object
if ([Array]$StubResources.Count -eq 0) {
    Write-Verbose "[Merge-StubResources] No stub resources found. Returning original pipeline resources."
    return $PipelineResources
}

# Now there are stub resources we need to merge these resources
Write-Verbose "[Merge-StubResources] Found stub resources. Proceeding with merging."

# Group the stub resources by the 'MergeWith' property
Write-Verbose "[Merge-StubResources] Grouping stub resources by 'MergeWith' property."
$GroupResources = $StubResources | Group-Object -Property merge_with

ForEach ($GroupResource in $GroupResources) {
    # Find the resource that the stub resource is to be merged with
    Write-Verbose "[Merge-StubResources] Looking for resources to merge with: $($GroupResource.Name)"
    
    # Split the 'MergeWith' property to get the target resource name and type
    $split = $GroupResource.Group[0].merge_with -split '\/|\\'
    $GroupResourceName = $split[-1]
    $GroupResourceType = $split[0..($split.Length - 2)] -join '/'

    $Resource = $Resources | Where-Object { $_.Name -eq $GroupResourceName -and $_.Type -eq $GroupResourceType }

    # If the resource is not found, write a warning and continue
    if ($null -eq $Resource) {
        Write-Warning "[Merge-StubResources] Resource not found: $($GroupResource.Name)"
        continue
    }

    # Merge the stub resource properties with resource properties.
    Write-Verbose "[Merge-StubResources] Merging properties of stub resources with target resource: $($Resource.Name)"
    $GroupResource.Group | ForEach-Object {
        $Resource.properties = Join-Properties -source $Resource.properties -merge $_.properties
        Write-Verbose "[Merge-StubResources] Merged properties for resource: $($Resource.Name)"
    }
}

Write-Verbose "[Merge-StubResources] Merging complete. Returning updated resources."
return $Resources
