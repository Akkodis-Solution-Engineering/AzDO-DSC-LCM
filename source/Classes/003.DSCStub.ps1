class DSCStub : DSCBaseResource {
    [string] $merge_with

    DSCStub ([HashTable] $ht) {
        # Ensure all mandatory properties are provided
        if ((-not($ht.name)) -or (-not ($ht.properties)) -or (-not($ht.merge_with) -or (-not($ht.type)))) {
            throw "[DSCStub] Error: All properties (name, type, properties, merge_with) must be provided."
        }

        $this.name = $ht.name
        $this.type = $ht.type
        $this.properties = $ht.properties
        $this.merge_with = $ht.merge_with

    }

    [DSC_Resource[]] merge([DSC_Resource[]]$dscResources) {

        # Locate the resource index position
        $indexPos = 0 .. ($dscResources.count - 1) | Where-Object {
            $dscResources[$_].getFullResourceName() -eq $this.merge_with.Replace("\", "/")
        }
    
        # If the resource is missing, throw an error
        if (@($indexPos).count -eq 0) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' not found in provided DSC resources."
        }
        # If there are multiple resources found, throw an error
        if ($indexPos.count -ne 1) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' was found multiple times (count $($indexPos.count) in provided DSC resources."
        }

        # Ensure that the resource contains the 'mergeable' property and is true. If not, block the merge.
        if (($null -eq $dscResources[$indexPos].'mergable') -or ($dscResources[$indexPos].'mergable' -eq $false)) {
            throw "[DSCStub] Error: Resource '$($this.merge_with)' does not contain a 'mergable' property."
        }

        # Merge the Properties
        $dscResources[$indexPos].properties = Join-Properties -source $dscResources[$indexPos].properties -merge $this.properties

        return $dscResources
        
    }

}

