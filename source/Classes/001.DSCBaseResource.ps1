class DSCBaseResource {
    [string] $name
    [string] $type  
    [hashtable]$properties

    [string] getFullResourceName() {
        
        # Check if the name and type properties are set
        if (($null -eq $this.name) -or ($null -eq $this.type)) {
            throw "[DSCBaseResource] Resource name is not set"
        }

        return "$($this.type)/$($this.name)".Replace("\", "/")
    }
    
}