class DSCCompositeResource : DSCBaseResource {

    hidden [string]$resourceName
    hidden [string]$linkedFileName
    [DSCConfigurationFile]$resource

    
    # DSC Composite Resources are the same as standard DSC Resources,
    # however composite resources are referenced as a module in the type
    # Therefore when the type is a DSC Resource, presume it's a composite
    # Resource

    DSCCompositeResource ([string]$compositeDirectory, [HashTable]$task, [String]$resource) {

        # Perform a lookup for the DSC Resource within the Composite Directory and verify that it exists
        $this.linkedFileName = Join-Path $compositeDirectory "$resource.yml"

        # Test if the Path Exists
        if (-not(Test-Path -LiteralPath $this.linkedFileName)) {

            # The composite resource does not exist
            throw "[DSCCompositeResource] Error. The composite resource cannot be found. Please check that the file is named correctly and try again. FilePath: $($this.linkedFileName)"

        }

        # Load the Configuration File as a Composite Resource

        $this.resource = [DSCConfigurationFile]::New($this.linkedFileName, $true)

    }

}