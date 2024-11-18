class DSCBaseResource {
    [string] $name
    [DSCResourceType] $type    
    [hashtable[]]$properties

    [string] getFullResourceName() {
        return "$($this.type)\$($this.name)"
    }
    
}