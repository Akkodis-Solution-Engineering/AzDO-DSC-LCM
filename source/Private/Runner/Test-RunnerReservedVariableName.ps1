<#
.SYNOPSIS
Tests whether a configuration variable name would overwrite a variable the runner or
PowerShell itself depends on.

.DESCRIPTION
Set-Variables and Set-CompositeScope create a script-scope variable for every configuration
variable, so postExecutionScript/preExecutionScript can read it directly. That scope is the
module's own scope, so a configuration variable named 'parameters', 'tasks' or
'ErrorActionPreference' would replace the runner's state or change its behavior.

A name is reserved when it is:
- a PowerShell automatic or preference variable, or
- a variable that already exists in the module scope and was not created from a
  configuration variable (tracked in $script:runnerScriptVariableNames).

.PARAMETER Name
The variable name, after '.' has been replaced with '_'.

.OUTPUTS
System.Boolean
#>
function Test-RunnerReservedVariableName {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Name
    )

    $automatic = @(
        '_', 'args', 'ConsoleFileName', 'Error', 'Event', 'EventArgs', 'EventSubscriber',
        'ExecutionContext', 'false', 'foreach', 'HOME', 'Host', 'input', 'IsCoreCLR', 'IsLinux',
        'IsMacOS', 'IsWindows', 'LASTEXITCODE', 'Matches', 'MyInvocation', 'NestedPromptLevel',
        'null', 'PID', 'PROFILE', 'PSBoundParameters', 'PSCmdlet', 'PSCommandPath', 'PSCulture',
        'PSDebugContext', 'PSEdition', 'PSHOME', 'PSItem', 'PSScriptRoot', 'PSSenderInfo',
        'PSUICulture', 'PSVersionTable', 'PWD', 'Sender', 'ShellId', 'StackTrace', 'switch',
        'this', 'true', 'env', 'OFS', 'PSDefaultParameterValues', 'PSEmailServer',
        'PSModuleAutoLoadingPreference', 'PSSessionApplicationName',
        'PSSessionConfigurationName', 'PSSessionOption', 'PSNativeCommandArgumentPassing',
        'PSStyle', 'MaximumHistoryCount', 'OutputEncoding'
    )

    if ($automatic -contains $Name -or $Name -like '*Preference') {
        return $true
    }

    $createdByRunner = ($null -ne $script:runnerScriptVariableNames) -and $script:runnerScriptVariableNames.Contains($Name)
    if (-not $createdByRunner -and $null -ne (Get-Variable -Name $Name -Scope Script -ErrorAction Ignore)) {
        return $true
    }

    return $false
}
