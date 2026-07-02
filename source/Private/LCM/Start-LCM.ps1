<#
.SYNOPSIS
Invokes the Desired State Configuration (DSC) based on a provided configuration file.

.DESCRIPTION
The Start-LCM function processes a DSC configuration file (YAML or JSON) and executes the tasks defined within it.
It supports both 'Test' and 'Set' modes to either validate the current state or apply changes to achieve the desired state.

.PARAMETER FilePath
The path to the configuration file (.yaml/.yml or .json).

.PARAMETER Mode
Specifies the mode of operation. Valid values are 'Test' (default) and 'Set'.
'Test' mode validates the current state, while 'Set' mode applies changes to achieve the desired state.

.PARAMETER ReportPath
Optional parameter to specify a path for saving the report. If provided, the report will be saved as a CSV file at the specified location.

.PARAMETER ContinueOnError
When specified, a resource failure does not stop processing. Resources that directly or transitively
depend on the failed resource are automatically marked as failed; all other resources continue to run.
Without this switch, the first Set failure halts all subsequent task processing.

.EXAMPLE
Start-LCM -FilePath "C:\Configs\MyConfig.yaml" -Mode "Test"
Invokes the DSC configuration in 'Test' mode using the specified YAML configuration file.

.EXAMPLE
Start-LCM -FilePath "C:\Configs\MyConfig.json" -Mode "Set" -ReportPath "C:\Reports"
Invokes the DSC configuration in 'Set' mode using the specified JSON configuration file and saves the report to the specified path.

.EXAMPLE
Start-LCM -FilePath "C:\Configs\MyConfig.yaml" -ConfigurationMode "Enforce" -ContinueOnError -DSCCompositeResourcePath "C:\Composite"
Runs in Enforce mode; if a resource fails its Set operation, dependent resources are skipped but independent resources continue.

.NOTES
- The function supports both YAML and JSON configuration files.
- The function processes tasks in the order of their dependencies.
- The function generates a detailed report of the execution, which can be saved to a specified path.

#>
#
# Function to Invoke the DSC Configuration
function Start-LCM {
    # Declare parameters for the function with default values and validation where needed
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath, # The path to the configuration file (.yaml/.yml or .json)
        [Parameter(Mandatory = $true)]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")] # Ensures that ConfigurationMode can only be one of the specified values
        [string] $ConfigurationMode, # The mode of operation for the LCM (e.g., ApplyOnly, Audit, Enforce, Scheduled)
        [string] $ReportPath = $null, # Optional parameter for specifying a report path
        [Parameter(Mandatory = $true)]
        [string] $DSCCompositeResourcePath,
        [switch] $ContinueOnError # When set, failed resources cascade to dependents but non-dependents continue
    )

    # Clear StopTaskProcessing variable
    $script:StopTaskProcessing = $false
    $references.Clear()

    # Track resource names that have failed (used when -ContinueOnError is active)
    $failedResources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $Mode = $( switch ($ConfigurationMode) {
        "ApplyOnly" { "Set" }
        "Audit" { "Test" }
        "Enforce" { "Set" }
        default { "Test" } # Default to Test if no match
    })

    Write-Verbose "Configuration Mode: $ConfigurationMode, Execution Mode: $Mode"

    $reporting = [System.Collections.Generic.List[PSCustomObject]]::New()

    $pipeline = [DSCConfigurationFile]::New($FilePath, $DSCCompositeResourcePath)

    $configName = (Split-Path -Leaf $FilePath) -replace '\.(yml|yaml|json)$', ''
    Write-Host ""
    Write-Host "  LCM: $configName   [Mode: $ConfigurationMode]" -ForegroundColor Cyan
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
    Write-Host "  Merging partial resources..." -ForegroundColor Gray

    $tasks = Invoke-CustomTask -Tasks $pipeline.resources -CustomTaskName "Merge-StubResources"

    Write-Host "  Sorting by dependency order..." -ForegroundColor Gray

    # Sort the tasks based on their dependencies to ensure correct execution order
    $tasks = Invoke-CustomTask -Tasks $Tasks -CustomTaskName "Sort-DependsOn"
    Write-Verbose "Sorted tasks based on dependencies"

    Write-Host "  Applying pre-parse rules..." -ForegroundColor Gray

    # Invoke the PreParse the rules to process the tasks before formatting them
    Invoke-PreParseRules -Tasks $Tasks

    Write-Host "  Formatting tasks..." -ForegroundColor Gray

    # Format the tasks based on the configuration rules
    $tasks = Invoke-FormatTasks -Tasks $tasks

    # Report Task Counter
    $TaskCounter = 0

    # Loop through each task/resource and process it according to its configuration
    foreach ($task in $tasks) {

        # Increment the task counter
        $TaskCounter++

        Write-Verbose "Processing resource: [$($task.type)/$($task.name)]"

        # If the StopTaskProcessing variable is set to true, stop processing the tasks
        if ($Script:StopTaskProcessing) {
            Write-Verbose "Skipping resource due to 'Stop-TaskProcessing' being called:"
            # Add a reporting entry for the skipped resource
            $null = $reporting.Add([PSCustomObject]@{
                Counter = $TaskCounter
                Name = $task.name
                Type = $task.type
                Status = "Skipped"
                Method = 'TEST'
                Result = "SKIPPED"
                Message = "Resource skipped due to 'Stop-TaskProcessing' cmdlet."
            })

            # Skip to the next task
            continue
        }

        # When -ContinueOnError is active, check if any dependency has already failed.
        # If so, cascade the failure to this resource and skip it.
        if ($ContinueOnError -and -not [string]::IsNullOrEmpty($task.dependsOn)) {

            $dependencyNames = @($task.dependsOn) | ForEach-Object {
                $parts = $_.Split('/')
                $parts[2..$parts.Length] -join '/'
            }

            $failedDep = $dependencyNames | Where-Object { $failedResources.Contains($_) } | Select-Object -First 1

            if ($null -ne $failedDep) {
                Write-Verbose "Skipping resource [$($task.type)/$($task.name)] - dependency '$failedDep' failed."
                $null = $reporting.Add([PSCustomObject]@{
                    Counter = $TaskCounter
                    Name    = $task.name
                    Type    = $task.type
                    Status  = "Skipped"
                    Method  = 'TEST'
                    Result  = "SKIPPED"
                    Message = "Resource skipped because dependency '$failedDep' failed."
                })
                $null = $failedResources.Add($task.name)
                continue
            }
        }

        # Evaluate the Condition script block if it exists, and skip the task if the condition returns false
        if ($null -ne $task.Condition) {

            # Create a script block from th econdition property
            $sbCondition = [scriptblock]::Create($task.Condition)

            if ((. $sbCondition) -eq $false) {

                Write-Verbose "Skipping resource due to condition: [$($task.type)/$($task.name)]"
                # Add a reporting entry for the skipped resource
                $null = $reporting.Add([PSCustomObject]@{
                    Counter = $TaskCounter
                    Name = $task.name
                    Type = $task.type
                    Status = "Skipped"
                    Method = 'TEST'
                    Result = "SKIPPED"
                    Message = "Resource skipped due to condition {$($task.Condition)}."
                })

                # Skip to the next task
                continue

            }
        }

        # Extract the module name and resource type from the task's type property
        $module = $task.type.Split("/")[0]
        $resourceType = $task.type.Split("/")[1]
        Write-Verbose "Extracted module name: $module and resource type: $resourceType"

        # Replace any variables in the properties with their actual values
        $Property = Expand-HashTable -InputHashTable $task.properties

        Write-Verbose "Replaced variables in properties with actual values"

        # Prepare parameters for invoking the DSC resource using the 'Test' method
        $resourceParameters = @{
            Name = $resourceType
            ModuleName = $module
            Method = "Test"
            Property = $Property
        }

        Write-Verbose "Prepared parameters for 'Test' invocation of DSC resource"

        # Execute the 'Test' method to determine if the state is as desired
        $result = Invoke-DscResource @resourceParameters
        Write-Verbose "Executed 'Test' method for DSC resource: [$($task.type)/$($task.name)]"

        # Update the reporting list with the result of the 'Test' operation
        $null = $reporting.Add([PSCustomObject]@{
            Counter = $TaskCounter
            Name    = $task.name
            Type    = $task.type
            Method  = 'TEST'
            Status  = $result.InDesiredState ? "InDesiredState" : "NotInDesiredState"
            Result  = $result.InDesiredState ? "PASS" : "FAIL"
            Message = $result.Message
        })

        # Set the execution mode based on the provided Mode parameter.
        $ExecutionMode = $Mode
        # If the task has an override for the execution method, use it.
        if ($task.executionMethodOverride -ne 'None') {
            Write-Verbose "Using custom execution method: $($task.executionMethodOverride)"
            $ExecutionMode = $task.executionMethodOverride
        }

        # Set Execution Processing Mode
        $CurrentTaskState = 'Continue'

        # If not in the desired state and Mode is 'Set', execute the 'Set' method to apply changes
        if ($result.InDesiredState) {
            Write-Verbose "Resource is in the desired state: [$($task.type)/$($task.name)]"
            Write-Verbose "No action taken as resource is already in the desired state: [$($task.type)/$($task.name)]"
        } elseif ($ExecutionMode -eq "Test") {
            Write-Verbose "Resource is NOT in the desired state and ExecutionMode is 'Test': [$($task.type)/$($task.name)]"
            Write-Verbose "No action taken as ExecutionMode is 'Test': [$($task.type)/$($task.name)]"
        }
        elseif ($ExecutionMode -eq "Set")
        {

            try {
                # Execute the 'Set' method to make changes
                $resourceParameters.Method = "Set"
                $setResult = Invoke-DscResource @resourceParameters
                Write-Verbose "Executed 'Set' method to make changes: [$($task.type)/$($task.name)]"
            } catch {
                # If the 'Set' method fails, log the error and continue
                Write-Error "Failed to apply changes with 'Set' method: [$($task.type)/$($task.name)]"
                $CurrentTaskState = 'Stop'

                $Message = $_.Exception.Message
                $Result = "FAIL"

                $reporting.Add([PSCustomObject]@{
                    Counter     = $TaskCounter
                    Name        = $task.name
                    Type        = $task.type
                    Status      = "Set"
                    Method      = "SET"
                    Result      = "FAIL"
                    Message     = $_.Exception.Message
                })
            }
        }

        # If the task is in 'Continue' state, however the configuration mode is 'ApplyOnly' or 'Enforce', handle the execution accordingly
        if (($CurrentTaskState -eq 'Continue') -and ($ConfigurationMode -eq "ApplyOnly") -and ($ExecutionMode -eq "Set")) {

            # If the configuration mode is 'ApplyOnly', apply the changes without testing again
            Write-Verbose "ConfigurationMode is 'ApplyOnly', applying changes without testing again: [$($task.type)/$($task.name)]"
            # Update the reporting list
            $null = $reporting.Add([PSCustomObject]@{
                Counter     = $TaskCounter
                Name        = $task.name
                Type        = $task.type
                Status      = "Set"
                Method      = "SET"
                Result      = "PASS"
                Message     = "Resource set to desired state in 'ApplyOnly' mode."
            })

        } elseif (($CurrentTaskState -eq 'Continue') -and ($ConfigurationMode -eq "Enforce") -and ($ExecutionMode -eq "Set")) {

            # If the configuration mode is 'Enforce', we need to ensure the resource is in the desired state
            try {
                # Retest the resource to ensure the changes were applied successfully
                $resourceParameters.Method = "Test"
                $result = Invoke-DscResource @resourceParameters
                Write-Verbose "Executed 'Test' method to verify changes: [$($task.type)/$($task.name)]"

                # If not in the desired state and Mode is 'Set', execute the 'Set' method to apply changes
                if ($result.InDesiredState) {
                    $Message = "Resource set to desired state"
                    $Result = "PASS"
                    Write-Verbose "Resource set to desired state: [$($task.type)/$($task.name)]"
                } else {
                    $Message = "Failed to set resource to desired state"
                    $Result = "FAIL"
                    Write-Verbose "Failed to set resource to desired state: [$($task.type)/$($task.name)]"
                }

            } catch {
                Write-Error "Failed to apply changes with 'Set' method: [$($task.type)/$($task.name)]"
                $Message = $_.Exception.Message
                $Result = "FAIL"
            }

            # Update the reporting list with the result of the 'Set' operation
            $null = $reporting.Add([PSCustomObject]@{
                Counter     = $TaskCounter
                Name        = $task.name
                Type        = $task.type
                Status      = "Set"
                Method      = "SET"
                Result      = $Result
                Message     = $Message
            })

        }

        #
        # Test if the postCondition property exists and execute the script block if it does.
        if ($null -ne $task.postExecutionScript) {
            # Create a script block from the postCondition property
            $sbPostExecutionScript = [scriptblock]::Create($task.postExecutionScript)

            # Dot-Source the postCondition script block
            . $sbPostExecutionScript
        }

        # Execute the 'Get' method to retrieve the current state of the resource
        $resourceParameters.Method = 'get'
        $output_var = Invoke-DscResource @resourceParameters
        Write-Verbose "Retrieved current state with 'Get' method for DSC resource: [$($task.type)/$($task.name)]"

        # Store the output of the 'Get' operation in a reference table for later use
        $references.Add($task.name, $output_var)
        Write-Verbose "Stored output of 'Get' operation in references table for resource: [$($task.type)/$($task.name)]"

        # Handle task failure: either stop all processing or track the failure for dependency cascading
        if ($CurrentTaskState -eq 'Stop') {
            if ($ContinueOnError) {
                $null = $failedResources.Add($task.name)
                Write-Verbose "Resource [$($task.type)/$($task.name)] failed. Continuing (ContinueOnError is set). Dependent resources will be skipped."
            } else {
                Write-Verbose "Resource [$($task.type)/$($task.name)] failed. Stopping all remaining task processing."
                $script:StopTaskProcessing = $true
            }
        }

    }

    #
    # Report the results of the DSC Configuration
    #

    $PassCounter = 0
    $FailCounter = 0
    $SkippedCounter = 0

    # Group by the task name and status to provide a summary of the results
    $reportSummary = $reporting | Group-Object -Property Name | Sort-Object -Property {$_.Group.Counter}

    # If the reporting path is specified, print the report to the console and save it to the specified path
    if ($ReportPath) {

        Write-Verbose "[Start-LCM] FilePath $FilePath"

        # Construct the full path for the report file
        $FilePath = "{0}\{1}.csv" -f $ReportPath, $($FilePath | Split-Path -Leaf).TrimEnd('.yml')

        # Convert the reporting data to CSV format and write it to the specified path
        $reporting | Export-Csv -Path $FilePath -NoTypeInformation

    }

    # Print the results table to the console.

    Write-Host ""
    Write-Host "  Results:" -ForegroundColor White
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray

    # Iterate through the grouped report data and display the results
    foreach ($GroupReport in $reportSummary) {

        $Counter = $GroupReport.Group.Counter | Select-Object -First 1

        if ($GroupReport.Count -gt 1) {

            $setResult = $GroupReport.Group | Where-Object { $_.Method -eq 'SET' }

            if ($setResult.Result -contains "PASS") {
                $Colour = "Green"
                $Result = "PASS"
                $PassCounter++
            } else {
                $Colour = "Red"
                $Result = "FAIL"
                $FailCounter++
            }

        } else {
            if ($GroupReport.Group.Result -contains "PASS") {
                $Colour = "Green"
                $Result = "PASS"
                $PassCounter++
            } elseif ($GroupReport.Group.Result -contains "FAIL") {
                $Colour = "Red"
                $Result = "FAIL"
                $FailCounter++
            } elseif ($GroupReport.Group.Result -contains "SKIPPED") {
                $Colour = "Yellow"
                $Result = "SKIPPED"
                $SkippedCounter++
            } else {
                $Colour = "Magenta"
                $Result = "UNKNOWN"
            }
        }

        $counterLabel = "[$($Counter.ToString().PadLeft(2))]"
        $resultLabel  = $Result.PadRight(8)
        Write-Host "  $counterLabel  $resultLabel  $($GroupReport.Name)" -ForegroundColor $Colour
    }

    $OutputColour = ($FailCounter -eq 0) ? "Green" : "Red"

    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
    Write-Host "Total Tasks Executed: $($reportSummary.Count)" -ForegroundColor $OutputColour
    Write-Host "Tasks Passed:  $PassCounter" -ForegroundColor $OutputColour
    Write-Host "Tasks Failed:  $FailCounter" -ForegroundColor $OutputColour
    Write-Host "Tasks Skipped: $SkippedCounter" -ForegroundColor $OutputColour
    Write-Host ""

}
