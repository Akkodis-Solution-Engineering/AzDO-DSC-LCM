# Custom Class that's responsible for parsing endpoint/composite resource configuration

class DSCConfigurationFile {

    [HashTable]$parameters
    [HashTable]$variables
    [HashTable[]]$resources
    hidden [bool]$isCompositeResource = $false
    [string]$configurationDirectory = $null
    [string]$compositeResourcePath = $null

    DSCConfigurationFile ([string]$configurationFile) {
        $this.isCompositeResource = $true
        $this.Load($configurationFile)
    }

    DSCConfigurationFile ([string]$configurationFile, [string]$DSCCompositeResourcePath) {
        $this.compositeResourcePath = $DSCCompositeResourcePath
        $this.Load($configurationFile)
    }

    # Load the Configuration File
    load([String] $configurationFile) {
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

        # Parse the Resources
        if ($null -eq $pipeline.resources) {
            $this.resources = ConvertTo-Resource -task $pipeline.resources -compositeResourcePath $this.compositeResourcePath
        }
        
        # Parse the Parameters
        if ($null -ne $pipeline.parameters) {
            # Load the parameters/ If the variables already exist in memory parse them in.
            $this.parameters = GetParameterValues -Source $pipeline.parameters
        }

        # Variables
        if ($null -ne $pipeline.variables) {
            $this.variables = SetVariables -Source $pipeline.variables
        }

        
    }

}