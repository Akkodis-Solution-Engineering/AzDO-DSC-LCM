<#
.SYNOPSIS
Projects a parsed class-based resource instance into the plain object shape the engine-agnostic
Start-DscRunner loop consumes.

.DESCRIPTION
The class hierarchy (DSCConfigurationFile -> ConvertTo-Resource -> DSC_Resource/DSCStub/
DSCCompositeResource) owns parsing, stub-merging and composite-expansion. Everything after that
- Expand-NotifyDependsOn, Sort-DependsOn, the PreParse rules and the engine loop in
Start-DscRunner (ported from Dsc.PipelineRunner) - was written against plain hashtables/
PSCustomObjects read straight off YAML, and reads/writes properties by name (including
DependsOn re-assignment in Expand-NotifyDependsOn). ConvertTo-PipelineTask is the thin seam
between the two: it copies a [DSC_Resource] instance's public properties onto a [pscustomobject],
which supports the same dot-notation get/set the ported rules rely on.

By the time this runs, only [DSC_Resource] instances should remain in the pipeline -
Merge-StubResources has already consumed every [DSCStub], and Expand-CompositeResources has
already replaced every [DSCCompositeResource] with its expanded inner [DSC_Resource]s.

.PARAMETER Resource
A DSC_Resource instance (accepts pipeline input from Expand-CompositeResources' output).

.OUTPUTS
[pscustomobject] carrying Name/Type/Properties/DependsOn/Notify/PreCondition/Condition/
PostCondition/PreExecutionScript/PostExecutionScript/Target/ResourceCredential/
ExecutionMethodOverride/Mergable - every key Start-DscRunner's engine loop reads.
#>
function ConvertTo-PipelineTask {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [DSC_Resource]
        $Resource
    )

    process {
        [pscustomobject]@{
            Name                    = $Resource.name
            Type                    = $Resource.type
            Properties              = $Resource.properties
            DependsOn               = [string[]]@($Resource.dependsOn)
            Notify                  = [string[]]@($Resource.notify)
            Condition                = $Resource.condition
            PreCondition             = $Resource.preCondition
            PostCondition            = $Resource.postCondition
            PreExecutionScript       = $Resource.preExecutionScript
            PostExecutionScript      = $Resource.postExecutionScript
            Target                   = $Resource.target
            ResourceCredential       = $Resource.resourceCredential
            ExecutionMethodOverride  = [string]$Resource.executionMethodOverride
            Mergable                 = $Resource.mergable
        }
    }
}
