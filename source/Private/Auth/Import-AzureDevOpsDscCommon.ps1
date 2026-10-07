<#
.SYNOPSIS
Imports AzureDevOpsDsc.Common, including the copy bundled inside AzureDevOpsDscNative.

.DESCRIPTION
New-AzDoAuthenticationProvider lives in AzureDevOpsDsc.Common. The AzureDevOpsDscNative
resource module does not install that module separately: it ships it under its own
Modules\AzureDevOpsDsc.Common folder, and every AzureDevOps resource's constructor then runs
`Import-Module AzureDevOpsDsc.Common` BY NAME. When no standalone copy is installed, this puts
the newest AzureDevOpsDscNative's Modules folder on PSModulePath for the process, so both the
import here and the resources' own imports resolve to the bundled copy.

.OUTPUTS
None. Throws when neither a standalone AzureDevOpsDsc.Common nor AzureDevOpsDscNative is
installed.
#>
function Import-AzureDevOpsDscCommon {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name 'AzureDevOpsDsc.Common')) {
        $native = Get-Module -ListAvailable -Name 'AzureDevOpsDscNative' |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($native) {
            $bundledModules = Join-Path -Path $native.ModuleBase -ChildPath 'Modules'
            $separator = [System.IO.Path]::PathSeparator
            if (($env:PSModulePath -split [regex]::Escape($separator)) -notcontains $bundledModules) {
                $env:PSModulePath = $bundledModules + $separator + $env:PSModulePath
            }
        }
    }

    try {
        Import-Module -Name 'AzureDevOpsDsc.Common' -ErrorAction Stop
    }
    catch {
        throw "Azure DevOps support requires the 'AzureDevOpsDscNative' module (or a standalone 'AzureDevOpsDsc.Common'). Install it with 'Install-Module AzureDevOpsDscNative'. Underlying error: $($_.Exception.Message)"
    }
}
