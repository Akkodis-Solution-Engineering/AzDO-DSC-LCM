class DSCBaseResource {
    [string] $name
    [DSCResourceType] $type    
    [hashtable[]]$Properties

    [string] getFullResourceName() {
        return "$($this.type)\$($this.name)"
    }
    
}