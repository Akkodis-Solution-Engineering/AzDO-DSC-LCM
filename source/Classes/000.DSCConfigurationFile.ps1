# Custom Class that's responsible for parsing endpoint/composite resource configuration

class DSCConfigurationFile {

    [HashTable]$parameters
    [HashTable]$variables
    [HashTable[]]$resources
    hidden [bool]$isCompositeResource = $false

    DSCConfigurationFile ([string]$configurationFile, [bool]$isCompositeResource) {
        $this.isCompositeResource = $isCompositeResource
        $this.Load($configurationFile)
    }

    DSCConfigurationFile ([string]$configurationFile) {
        $this.Load($configurationFile)
    }

    # Load the Configuration File
    Load([String] $configurationFile) {
        # Determine the file extension of the provided FilePath
        $fileExtension = [System.IO.Path]::GetExtension($configurationFile)
        Write-Verbose "File extension determined: $fileExtension"

        if ($fileExtension -eq ".yaml" -or $fileExtension -eq ".yml") {
            $pipeline = Get-Content $configurationFile | ConvertFrom-Yaml
            Write-Verbose "Loaded YAML configuration from file: $configurationFile"
        }
        elseif ($fileExtension -eq ".json") {
            $pipeline = Get-Content $configurationFile | ConvertFrom-Json -AsHashtable
            Write-Verbose "Loaded JSON configuration from file: $configurationFile"
        } else {
            throw "[DSCResources] Unknown file extension ($fileExtension)"
        }

        $this.resources = $pipeline.resources

        if ($null -ne $pipeline.parameters) {
            # Load the parameters/ If the variables already exist in memory parse them in.
            $this.parameters = GetParameterValues -Source $pipeline.parameters
        }

        if ($null -ne $pipeline.variables) {
            $this.variables = SetVariables -Source $pipeline.variables
        }

    }

}