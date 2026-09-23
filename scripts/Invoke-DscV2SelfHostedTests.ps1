<#
.SYNOPSIS
Run the self-hosted DSC v2 environment-lifecycle integration suite (tag 'DscV2SelfHosted').

.DESCRIPTION
Drives DscV2Engine-RealInvokeDscResource.Integration.tests.ps1, which exercises
Actions/Engine/DscV2.ps1 against a real Invoke-DscResource / PSDesiredStateConfiguration
lifecycle (Test/Set/Get) using the PipelineRunnerFile class-based DSC resource fixture under
Tests/Fixtures/DscV2, instead of the mocked Invoke-DscResource the unit suite uses.

Kept separate from the default tests.ps1 run because Invoke-DscResource is only reliably
available on a machine with PSDesiredStateConfiguration properly registered, which the
self-hosted runner provides. This is what the WinRM/DSCv2/DSCv3 self-hosted workflow job
invokes; it can also be run by hand on the runner.

.PARAMETER RepositoryRoot
Repository root. Defaults to the parent of this script's folder.

.OUTPUTS
None. Sets a non-zero exit code (Run.Exit) when any test fails, so a CI step turns red.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $RepositoryRoot

# Use Pester v5 explicitly; a stale built-in Pester (v3 on Windows) would break
# New-PesterConfiguration if it auto-loaded first.
Import-Module -Name Pester -MinimumVersion '5.0.0' -MaximumVersion '5.9999.9999' -Force -ErrorAction Stop

# Provides Get-FunctionPath and (re)initializes $Global:RepositoryRoot for the test bootstrap.
Import-Module -Name (Join-Path $RepositoryRoot 'Tests/TestHelpers/CommonTestFunctions.psm1') -Force
Remove-Variable -Name RepositoryRoot -Scope Global -ErrorAction SilentlyContinue
Remove-Variable -Name TestPaths      -Scope Global -ErrorAction SilentlyContinue

$config = New-PesterConfiguration
$config.Run.Path         = Join-Path $RepositoryRoot 'Tests/PipelineRunner/Intergration/Tests/DscV2Engine-RealInvokeDscResource.Integration.tests.ps1'
$config.Filter.Tag       = @('DscV2SelfHosted')
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit         = $true

Invoke-Pester -Configuration $config
