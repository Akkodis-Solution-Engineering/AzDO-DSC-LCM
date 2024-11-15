class DSCResource : DSCBaseResource {
    [string] $condition
    [string] $postExecutionScript
    [string] $dependsOn
    [bool] $mergable = $false

    DSCResource([hashtable]$ht) {
        # Name, Type, Properties are mandatory

        if (-not $ht.ContainsKey('name')) {
            throw "Name is mandatory"
        }
        if (-not $ht.ContainsKey('type')) {
            throw "Type is mandatory"
        }
        # Properties is mandatory
        if (($null -eq $ht.properties) -and ($ht.properties -isnot [hashtable[]])) {
            throw "Properties is mandatory"
        }

        $this.name = $ht['name']
        $this.type = $ht['type']
        $this.properties = $ht['properties']

        $this.condition = $ht['condition']
        $this.postExecutionScript = $ht['postExecutionScript']
        $this.dependsOn = $ht['dependsOn']
        $this.mergable = $ht['mergable']

    }

}

Function Merge-DSCResourceProperties {
    param(
        [Hashtable[]]$resourceProperties,
        [Hashtable[]]$stubProperties
    )


}