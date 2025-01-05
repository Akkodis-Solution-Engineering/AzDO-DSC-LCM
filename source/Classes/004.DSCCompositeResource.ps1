class DSCCompositeResource : DSCBaseResource {

    [hashtable]$inputParameters
    [string]$outputParameters

    hidden [string]$resourceName
    hidden [string]$linkedFileName
    [DSCConfigurationFile]$resource

    #
    # When executed, the resource will return each of the executed resources and it's final state.

    # DSC Composite Resources are the same as standard DSC Resources,
    # however composite resources are referenced as a module in the type
    # Therefore when the type is a DSC Resource, presume it's a composite
    # Resource

    DSCCompositeResource ([String]$resource, [string]$compositeDirectory, [HashTable]$task) {

        $this.name = $task.name
        $this.properties = $task.properties
        $this.type = $task.type

        # Perform a lookup for the DSC Resource within the Composite Directory and verify that it exists
        $this.linkedFileName = Join-Path $compositeDirectory "$resource.yml"

        # Test if the Path Exists
        if (-not(Test-Path -LiteralPath $this.linkedFileName)) {

            # The composite resource does not exist
            throw "[DSCCompositeResource] Error. The composite resource cannot be found. Please check that the file is named correctly and try again. FilePath: $($this.linkedFileName)"

        }

        # Load the Configuration File as a Composite Resource
        $this.resource = [DSCConfigurationFile]::New($this.linkedFileName)

    }

    [HashTable] Invoke([String]$LCMMode, [String]$DatumConfigurationPath) {

        # Once the Job has been executed, the output will be returned
        [HashTable]$output = @{}

        # Create a ScriptBlock to execute the Composite Resource
        $scriptBlock = {
            param(
                [String]$Mode,
                [String]$DatumConfigurationPath,
                [String]$CompositeFileName
            )
    
            $params = @{
                Mode = $Mode
                DSCCompositeResourcePath = Join-Path $DatumConfigurationPath 'CompositeResources'
                FilePath = $CompositeFileName
                OutputObject = LCMResult
            }

            # Execute the Composite Resource
            Invoke-CompositeResource @params

            # Return the Output Object
            return $Global:LCMResult

        }

        $startJobParams = @{
            ScriptBlock = $scriptBlock
            ArgumentList = @($LCMMode, $DatumConfigurationPath, $this.linkedFileName)
        }

        $output = Start-Job @startJobParams | Wait-Job | Receive-Job

        return $output

    }

}