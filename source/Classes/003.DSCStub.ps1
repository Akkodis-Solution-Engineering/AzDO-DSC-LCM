class DSCStub : DSCBaseResource {
    [string] $merge_with

    DSCStub ([HashTable] $ht) {
        # Ensure all mandatory properties are provided
        if ((-not($ht.name)) -or (-not ($ht.type)) -or (-not ($ht.properties)) -or (-not($ht.merge_with))) {
            throw "[DSCStub] Error: All properties (name, type, properties, merge_with) must be provided."
        }

        $this.name = $ht.name
        $this.type = $ht.type
        $this.Properties = $ht.properties
        $this.merge_with = $ht.merge_with

    }

    [DSCResource[]] merge([DSCResource[]]$dscResources) {

        # Locate the resource index position
        $indexPos = 0 .. $dscResources.count | Where-Object {
            $dscResources[$_].getFullResourceName() -eq $this.merge_with
        }

        # If the resource is missing, throw an error
        if (-not $indexPos) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' not found in provided DSC resources."
        }
        # If there are multiple resources found, throw an error
        if (-not $indexPos.count -ne 1) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' was found multiple times (count $($indexPos.count) in provided DSC resources."
        }

        # Ensure that the resource contains the 'mergeable' property and is true. If not, block the merge.
        if ($dscResources[$_].'mergeable' -eq $false) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' does not contain a 'mergeable' property."
        }

        # Merge the Properties
        $dscResources[$_].properties = mergeProperties -source $dscResources[$_].properties -merge $this.properties

        return $dscResources
        
    }

}

