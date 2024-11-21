class DSCYAMLResource : DSCBaseResource {
    [string] $condition
    [string] $postExecutionScript
    [string] $dependsOn
    [bool] $mergable = $false

    DSCYAMLResource([hashtable]$ht) {

        # Name, Type, Properties are mandatory
        if (-not $ht.ContainsKey('name')) {
            throw "[DSCYAMLResource] Name is mandatory"
        }
        # Properties is mandatory
        if (($null -eq $ht.properties) -and ($ht.properties -isnot [hashtable[]])) {
            throw "[DSCYAMLResource] Properties is mandatory"
        }

        $this.name = $ht['name']
        $this.type = [DSCResourceType]::Resource
        $this.properties = $ht['properties']

        $this.condition = $ht['condition']
        $this.postExecutionScript = $ht['postExecutionScript']
        $this.dependsOn = $ht['dependsOn']
        $this.mergable = $ht['mergable']

    }

}
