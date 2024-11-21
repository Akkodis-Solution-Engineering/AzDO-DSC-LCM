class DSC_Resource : DSCBaseResource {
    [string] $condition
    [string] $postExecutionScript
    [string] $dependsOn
    [bool] $mergable = $false

    DSC_Resource([hashtable]$ht) {

        # Name, Type, Properties are mandatory
        if (-not $ht.ContainsKey('name')) {
            throw "[DSC_Resource] Name is mandatory"
        }
        # Properties is mandatory
        if (($null -eq $ht.properties) -and ($ht.properties -isnot [hashtable[]])) {
            throw "[DSC_Resource] Properties is mandatory"
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
