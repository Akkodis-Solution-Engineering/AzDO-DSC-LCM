class DSC_Resource : DSCBaseResource {
    [string] $condition
    [string] $postExecutionScript
    [string] $dependsOn = $null
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

        if ($ht.ContainsKey('condition')) {
            $this.condition = $ht['condition']
        }
        if ($ht.ContainsKey('postExecutionScript')) {
            $this.postExecutionScript = $ht['postExecutionScript']
        }
        if ($ht.ContainsKey('dependsOn')) {
            $this.dependsOn = $ht['dependsOn']
        }
        if ($ht.ContainsKey('mergable')) {
            $this.mergable = $ht['mergable']
        }

    }

}
