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

When neither is installed, AzureDevOpsDscNative is installed from the PowerShell Gallery for
the current user (Install-Module -Scope CurrentUser), so no elevation is needed.

.OUTPUTS
None. Throws when AzureDevOpsDsc.Common still cannot be imported.
#>
function Import-AzureDevOpsDscCommon {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name 'AzureDevOpsDsc.Common')) {
        $native = Get-Module -ListAvailable -Name 'AzureDevOpsDscNative' |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if (-not $native) {
            Write-Warning "[Import-AzureDevOpsDscCommon] AzureDevOpsDscNative is not installed; installing it for the current user."
            try {
                Install-Module -Name 'AzureDevOpsDscNative' -Scope CurrentUser -Repository PSGallery -Force -ErrorAction Stop
            }
            catch {
                throw "Azure DevOps support requires the 'AzureDevOpsDscNative' module, and installing it for the current user failed. Install it with 'Install-Module AzureDevOpsDscNative -Scope CurrentUser'. Underlying error: $($_.Exception.Message)"
            }

            $native = Get-Module -ListAvailable -Name 'AzureDevOpsDscNative' |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1
        }

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
        throw "Azure DevOps support requires the 'AzureDevOpsDscNative' module (or a standalone 'AzureDevOpsDsc.Common'). Install it with 'Install-Module AzureDevOpsDscNative -Scope CurrentUser'. Underlying error: $($_.Exception.Message)"
    }
}
