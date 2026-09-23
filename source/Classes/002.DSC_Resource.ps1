class DSC_Resource : DSCBaseResource {
    # 'condition' is kept as a back-compat alias for 'preCondition' (the current name used by
    # the engine loop). Either key in the source hashtable sets both properties so a caller
    # reading either one sees the same value; preCondition wins if a resource somehow carries
    # both distinct values.
    [string] $condition
    [string] $preCondition
    [string] $postCondition
    [string] $postExecutionScript
    [string] $preExecutionScript

    # DependsOn/Notify accept either a single "Type/Name" string or an array of them in the
    # source YAML/JSON; PowerShell auto-wraps a scalar assigned to a typed array property into
    # a one-element array, so both forms land here as [string[]] without extra handling. This
    # is required by Sort-DependsOn/Expand-NotifyDependsOn (ported from Dsc.PipelineRunner),
    # which iterate DependsOn/Notify as a collection.
    [string[]] $dependsOn = @()
    [string[]] $notify = @()

    # #57-style resource lifecycle additions ported from Dsc.PipelineRunner: a declarative
    # remote target and a declarative credential resolution block. Both are passed through
    # to ConvertTo-PipelineTask untouched; Start-DscRunner resolves them via Invoke-Action.
    [hashtable] $target
    [hashtable] $resourceCredential

    [bool] $mergable = $false
    [ExecutionMethod] $executionMethodOverride = 'None'

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
            $this.preCondition = $ht['condition']
        }

        if ($ht.ContainsKey('preCondition')) {
            $this.preCondition = $ht['preCondition']
            $this.condition = $ht['preCondition']
        }

        if ($ht.ContainsKey('postCondition')) {
            $this.postCondition = $ht['postCondition']
        }

        if ($ht.ContainsKey('postExecutionScript')) {
            $this.postExecutionScript = $ht['postExecutionScript']
        }

        if ($ht.ContainsKey('preExecutionScript')) {
            $this.preExecutionScript = $ht['preExecutionScript']
        }

        if ($ht.ContainsKey('dependsOn') -and ($null -ne $ht['dependsOn'])) {
            $this.dependsOn = @($ht['dependsOn'])
        }

        if ($ht.ContainsKey('notify') -and ($null -ne $ht['notify'])) {
            $this.notify = @($ht['notify'])
        }

        if ($ht.ContainsKey('target')) {
            $this.target = $ht['target']
        }

        if ($ht.ContainsKey('resourceCredential')) {
            $this.resourceCredential = $ht['resourceCredential']
        }

        if ($ht.ContainsKey('mergable')) {
            $this.mergable = $ht['mergable']
        }

        if ($ht.ContainsKey('executionMethodOverride')) {

            try {
                $this.executionMethodOverride = [ExecutionMethod]$ht['executionMethodOverride']
            } catch {
                throw "[DSC_Resource] Invalid executionMethodOverride value: $($_.Exception.Message). Valid values are: 'Test', 'Set', 'None'."
            }

        }

    }

}
