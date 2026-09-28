<#
.SYNOPSIS
Resets the runner's parameter/variable scope to the file's baseline and applies a resource's
composite scope layers on top.

.DESCRIPTION
Start-DscRunner calls this before each resource. The module-scope $parameters and $variables
hashtables are restored to the configuration file's own values, then each layer in
CompositeScope (outermost composite first, see Expand-CompositeResources) is applied over them.
Layer values are resolved in the scope built so far, so a composite node's properties can
reference the parent file's parameters and variables.

Script-scope variables (read by preExecutionScript/postExecutionScript) are kept in step:
a composite variable is visible to that resource's scripts, and is put back to the file's
value (or removed) for the next resource.

.PARAMETER CompositeScope
The resource's composite scope layers. Empty for a resource that did not come from a
composite, which just restores the baseline.

.PARAMETER BaselineParameters
A copy of the file's parameters, taken before the first resource runs.

.PARAMETER BaselineVariables
A copy of the file's variables, taken before the first resource runs.
#>
function Set-CompositeScope {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $CompositeScope,

        [Parameter(Mandatory)]
        [hashtable] $BaselineParameters,

        [Parameter(Mandatory)]
        [hashtable] $BaselineVariables
    )

    # Script variables a previous resource's composite layer created or changed.
    if ($null -eq $script:compositeScopeVariableNames) {
        $script:compositeScopeVariableNames = [System.Collections.Generic.HashSet[string]]::new()
    }
    foreach ($name in @($script:compositeScopeVariableNames)) {
        $baselineKey = @($BaselineVariables.Keys) | Where-Object { $_.Replace('.', '_') -eq $name } | Select-Object -First 1
        if ($null -ne $baselineKey) {
            Set-Variable -Name $name -Value $BaselineVariables[$baselineKey] -Scope Script -Force
        } else {
            Remove-Variable -Name $name -Scope Script -Force -ErrorAction SilentlyContinue
        }
    }
    $script:compositeScopeVariableNames.Clear()

    $parameters.Clear()
    foreach ($key in $BaselineParameters.Keys) { $parameters[$key] = $BaselineParameters[$key] }
    $variables.Clear()
    foreach ($key in $BaselineVariables.Keys) { $variables[$key] = $BaselineVariables[$key] }

    foreach ($layer in @($CompositeScope)) {
        if ($null -eq $layer) { continue }

        if ($layer.Parameters -and $layer.Parameters.Count -gt 0) {
            $resolved = Expand-HashTable -InputHashTable (Expand-Parameters -InputHashTable $layer.Parameters)
            foreach ($key in $resolved.Keys) { $parameters[$key] = $resolved[$key] }
        }

        if ($layer.Variables -and $layer.Variables.Count -gt 0) {
            $resolved = Expand-HashTable -InputHashTable (Expand-Parameters -InputHashTable $layer.Variables)
            foreach ($key in $resolved.Keys) {
                $variables[$key] = $resolved[$key]
                $name = $key.Replace('.', '_')
                if (Test-RunnerReservedVariableName -Name $name) {
                    Write-Warning "[Set-CompositeScope] Variable '$key' in composite '$($layer.Composite)' shares its name with a runner variable and is only available through variables('$key')."
                    continue
                }
                Set-Variable -Name $name -Value $resolved[$key] -Scope Script -Force
                $null = $script:compositeScopeVariableNames.Add($name)
            }
        }
    }
}
