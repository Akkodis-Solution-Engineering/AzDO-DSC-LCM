<#
.SYNOPSIS
    Custom Class responsible for parsing endpoint/composite resource configuration.

.DESCRIPTION
    The DSCConfigurationFile class is designed to load and parse configuration files in YAML or JSON format. 
    It handles the extraction of parameters, variables, and resources from the configuration file.

.PARAMETER parameters
    A hashtable containing the parameters defined in the configuration file.

.PARAMETER variables
    A hashtable containing the variables defined in the configuration file.

.PARAMETER resources
    An array of hashtables containing the resources defined in the configuration file.

.PARAMETER isCompositeResource
    A hidden boolean indicating whether the configuration file is for a composite resource.

.PARAMETER configurationDirectory
    A string representing the directory of the configuration file.

.PARAMETER compositeResourcePath
    A string representing the path to the composite resource.

.CONSTRUCTOR
    DSCConfigurationFile ([string]$configurationFile)
        Initializes a new instance of the DSCConfigurationFile class and loads the configuration file.

    DSCConfigurationFile ([string]$configurationFile, [string]$DSCCompositeResourcePath)
        Initializes a new instance of the DSCConfigurationFile class with a specified composite resource path and loads the configuration file.

.METHODS
    load([String] $configurationFile)
        Loads the configuration file and parses its content based on the file extension (YAML or JSON).
        - Parses the resources, parameters, and variables from the configuration file.

.NOTES
    File Name: 000.DSCConfigurationFile.ps1
    Author: [Your Name]
    Date: [Date]

.EXAMPLE
    # Example of creating a DSCConfigurationFile object and loading a configuration file
    $configFile = [DSCConfigurationFile]::new("C:\path\to\config.yaml")
    $configFile.load("C:\path\to\config.yaml")

#>
# Custom Class that's responsible for parsing endpoint/composite resource configuration

class DSCConfigurationFile {

    [HashTable]$parameters
    [HashTable]$variables
    [HashTable[]]$resources
    hidden [string]$configurationFilePath
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

        $this.configurationFilePath = $configurationFile

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
        if ($null -ne $pipeline.resources) {
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