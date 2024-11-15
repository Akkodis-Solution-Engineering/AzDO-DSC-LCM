class DSCHelper {

    [string]$configurationSourcePath = $ConfigurationSourcePath
    [string]$compositeDirectory = $null

    DSCHelper ([string]$configurationSourcePath) {

        # Composite Directory
        $this.compositeDirectory = Join-Path $configurationSourcePath 'CompositeResources'
        $this.configurationSourcePath = $configurationSourcePath

        # Confirm that the source path is correct
        if (-not(Test-Path -LiteralPath $this.compositeDirectory)) {
            throw "[DSCHelper] Configuration Source Path is incorrect"
        }


    }

    [Object] convertToResource([HashTable]$Task) {

        switch ($Task) {

            # If the 'Type' of the resource prefixed with 'composite', rather then
            # azuredevopsdsc is it a composite resource.
            { $Task.Type -match '^composite(\\||\/)(?<resource>.+$)' } {
                # Parse the Composite Resource
                return [DSCCompositeResource]::New($this.compositeDirectory, $Task, $Matches.resource)
                
            }
            #
            { $null -ne $Task.MergeWith } {
                # Parse as a DSCStub.
                return [DSCStub]::New($this.Task)
            }
            # All other properties are treated as DSC resources.
            default {
                return [DSCResource]::New($Task)
            }

        }

        return $null
        
    }

}