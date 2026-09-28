
<#
.SYNOPSIS
    Sets variables from a source hashtable to a target hashtable and creates corresponding environment variables.

.DESCRIPTION
    The SetVariables function takes two hashtable parameters: $Source and $Target. It iterates through each key in the $Source hashtable, adds the key-value pair to the $Target hashtable, and creates a new variable in the script scope with the key name (dots replaced by underscores). Additionally, it creates an environment variable with the same name.

    Names that would overwrite the runner's own state or a PowerShell automatic/preference
    variable (see Test-RunnerReservedVariableName) are not created as script variables, and an
    environment variable that already existed before the runner set it (for example PATH or
    HOME) is never overwritten. Both cases write a warning; the value is still readable through
    the $Target hashtable (variables()/parameters()).

.PARAMETER Source
    The source hashtable containing the variables to be set.

.PARAMETER Target
    The target hashtable where the variables from the source hashtable will be added.

.EXAMPLE
    $source = @{ "key1" = "value1"; "key2" = "value2" }
    $target = @{}
    SetVariables -Source $source -Target $target

    This example sets the variables from the $source hashtable to the $target hashtable and creates corresponding script scope and environment variables.
#>
function Set-Variables {
    [CmdletBinding()]
    [Alias('SetVariables')]
    param (
        [hashtable] $Source,
        [hashtable] $Target
    )

    if ($null -eq $script:runnerScriptVariableNames) {
        $script:runnerScriptVariableNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    if ($null -eq $script:runnerEnvironmentVariableNames) {
        $script:runnerEnvironmentVariableNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    foreach ($key in $Source.Keys) {
        $Target[$key] = $Source[$key]

        $varName = $key.Replace(".", "_")

        if (Test-RunnerReservedVariableName -Name $varName) {
            Write-Warning "[Set-Variables] '$key' shares its name with a runner or PowerShell variable, so it is not created as `$$varName. Read it with variables('$key') or parameters('$key') instead."
        }
        else {
            New-Variable -Name $varName -Value $Source[$key] -Scope Script -Force | Out-Null
            $null = $script:runnerScriptVariableNames.Add($varName)
        }

        # Only write environment variables the runner owns: never overwrite one that existed
        # before the runner set it (PATH, HOME, TEMP, ...).
        $envExists = Test-Path -LiteralPath "env:$varName"
        if ($envExists -and -not $script:runnerEnvironmentVariableNames.Contains($varName)) {
            Write-Warning "[Set-Variables] Environment variable '$varName' already exists and is not overwritten."
            continue
        }
        # Use the interpolated variable name (env:$varName), not the literal string
        # "varName", and Set-Item so an existing environment variable is updated.
        Set-Item -Path "env:$varName" -Value $Source[$key] -ErrorAction SilentlyContinue | Out-Null
        $null = $script:runnerEnvironmentVariableNames.Add($varName)
    }
}
