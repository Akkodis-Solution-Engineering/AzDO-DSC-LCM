function ConvertTo-Resource {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [HashTable]
        $task,
        [Parameter(Mandatory)]
        $compositeResourcePath
    )

    Begin {
        $list = [System.Collections.ArrayList]::New()
    }

    Process {

        switch ($task) {

            # If the 'Type' of the resource prefixed with 'composite', rather then
            # azuredevopsdsc is it a composite resource.
            { $task.Type -match '^composite(\\|\/)(?<resource>.+$)' } {
                # Parse the Composite Resource
                $null = $task.Type -match '^composite(\\|\/)(?<resource>.+$)'
                $null = $list.Add([DSCCompositeResource]::New($matches.resource, $compositeResourcePath, $task))
                break
            }
            # If the property 'merge_with' is set, then it's a DSCStub.
            { $null -ne $task.merge_with } {
                # Parse as a DSCStub.
                $null = $list.Add([DSCStub]::New($task))
                break
            }
            # All other properties are treated as DSC resources.
            default {
                $null = $list.Add([DSC_Resource]::New($task))
                break
            }

        }

    }

    End {
        return $list
    }

}