<#
.SYNOPSIS
Invokes the DSC pipeline runner against a Datum configuration source, independent of any
specific DSC resource module or hosting platform.

.DESCRIPTION
Invoke-DscRunner resolves a configuration source (a local directory, or a git URL cloned
through Dsc.PipelineRunner's hardened Clone-Repository — https/ssh only, optional commit-SHA
pinning and verification), compiles it with Datum, validates it, resolves the
ApplyOnly/Audit/Enforce ConfigurationMode, and invokes Start-DscRunner against every exported
per-node configuration file, then folds the per-file results into one run summary via
Merge-DscRunnerResult.

Unlike Invoke-DscPipelineRunner, this function performs no platform authentication of its own.
If the resources referenced by your configuration's `type:` fields require an authenticated
connection, authenticate using that resource module's own mechanism before calling this
function.

.PARAMETER exportConfigDir
Specifies the directory where configuration files are exported by Datum. This parameter is mandatory and must be a valid directory path.

.PARAMETER ConfigurationSourcePath
Specifies the URL or directory path for the configuration source. This parameter is mandatory.

.PARAMETER ConfigurationRevision
Optional branch, tag, or commit to pin a remote (git) configuration source to. Ignored for a
local directory source. Supplying a full 40-character commit SHA makes the pin exact — the
clone's HEAD is verified against it (see Clone-Repository).

.PARAMETER ConfigurationMode
Specifies the pipeline runner mode to use. Valid values are 'ApplyOnly', 'Audit', and 'Enforce'. This parameter is optional; if not provided, the mode will be determined from the Datum configuration.

.PARAMETER ReportPath
Specifies the path to the report file. This parameter is optional and must be a valid directory path.

.PARAMETER ContinueOnError
When specified, a resource Set failure does not halt the run. Instead, resources that directly or transitively depend on the failed resource are automatically skipped; all others continue normally.

.PARAMETER Engine
Execution engine action (Actions/Engine/<Engine>.ps1). Default 'DscV2' (Invoke-DscResource).
'DscV3' drives dsc.exe. When not explicitly supplied, the resolved PipelineRunnerSettings.Engine
value from the configuration's Datum.yml (if any) is used instead.

.PARAMETER EngineVersion
Optional resource version hint that biases 'Auto' engine selection by major version.

.PARAMETER EngineAction
Optional inline engine override scriptblock; takes precedence over -Engine.

.PARAMETER FailOnError
Opt-in switch. When the aggregated run status is Failed or Aborted, sets the process exit code
to 1 (via Merge-DscRunnerResult) so a pipeline step fails loudly.

.PARAMETER KeepTemporaryDirectory
Leave any temporary directory this function created (a git clone) on disk after the run
instead of deleting it. A caller-supplied local directory is never deleted, with or without
this switch.

.EXAMPLE
Invoke-DscRunner -exportConfigDir "C:\Configs" -ConfigurationSourcePath "https://repo.url" -ConfigurationMode "Audit"

This example compiles and runs the configuration in 'Audit' mode.

#>
function Invoke-DscRunner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [String]$exportConfigDir,

        [Parameter(Mandatory)]
        [String]$ConfigurationSourcePath,

        [Parameter()]
        [String]$ConfigurationRevision,

        [Parameter()]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")]
        [AllowEmptyString()]
        [String]$ConfigurationMode,

        [Parameter()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [String]$ReportPath,

        [Parameter()]
        [Switch]$ContinueOnError,

        [Parameter()]
        [string]$Engine = 'DscV2',

        [Parameter()]
        [string]$EngineVersion,

        [Parameter()]
        [scriptblock]$EngineAction,

        [Parameter()]
        [Switch]$FailOnError,

        [Parameter()]
        [Switch]$KeepTemporaryDirectory
    )

    # Set the Error Action Preference
    $ErrorActionPreference = "Stop"

    $DatumConfigurationPath = $null

    try {

        #
        # Resolve the Configuration Source. A remote source is cloned through
        # Clone-Repository, which rejects anything but https/ssh (Assert-SecureGitUrl) and
        # verifies -ConfigurationRevision against the clone's HEAD when it is a full commit SHA.

        $sourceIsRemote = $ConfigurationSourcePath -match '^(https|ssh|git)://' -or $ConfigurationSourcePath -match '^[^\s@]+@[^\s:]+:'

        if ($sourceIsRemote) {
            $DatumConfigurationPath = Clone-Repository -DatumURLConfig $ConfigurationSourcePath -Revision $ConfigurationRevision
        }
        elseif (Test-Path -Path $ConfigurationSourcePath -PathType Container) {
            $DatumConfigurationPath = $ConfigurationSourcePath
        }
        else {
            throw "[Invoke-DscRunner] Invalid ConfigurationSourcePath: $ConfigurationSourcePath"
        }

        #
        # Compile the Datum Configuration
        Build-DatumConfiguration -OutputPath $exportConfigDir -ConfigurationPath $DatumConfigurationPath -AllowedRoot $exportConfigDir -SourceIsRemote:$sourceIsRemote

        #
        # Read and validate the Datum Configuration

        $DatumConfiguration = Get-Content -Path (Join-Path $DatumConfigurationPath 'datum.yml') | ConvertFrom-Yaml
        Test-DatumConfiguration -Datum @{ '__Definition' = $DatumConfiguration }

        #
        # Determine the Runner Configuration Mode

        if (-not $ConfigurationMode) {
            $ConfigurationMode = Get-PipelineRunnerConfigurationMode -DatumConfigurationMode $DatumConfiguration.PipelineConfigurationMode
        }

        #
        # Resolve RunnerSettings (Engine/Reboot/Target/AllowExecutionScripts) from the
        # source configuration's Datum.yml. Only present pre-compile - the compiled per-node
        # YAML files in $exportConfigDir do not carry it.

        $runnerSettings = Get-PipelineRunnerSetting -ConfigurationDirectory $DatumConfigurationPath
        if (-not $runnerSettings) { $runnerSettings = @{} }

        $resolvedEngine = $Engine
        if (-not $EngineAction -and -not $PSBoundParameters.ContainsKey('Engine') -and -not [string]::IsNullOrWhiteSpace([string]$runnerSettings['Engine'])) {
            $resolvedEngine = [string]$runnerSettings['Engine']
            Write-Verbose "[Invoke-DscRunner] Engine from PipelineRunnerSettings.Engine: $resolvedEngine"
        }

        #
        # Invoke the Resources

        $params = @{
            ConfigurationMode        = $ConfigurationMode
            DSCCompositeResourcePath = Join-Path $DatumConfigurationPath 'CompositeResources'
            Engine                   = $resolvedEngine
            RunnerSettings           = $runnerSettings
        }

        if ($ReportPath)      { $params.ReportPath      = $ReportPath }
        if ($ContinueOnError) { $params.ContinueOnError  = $true }
        if ($EngineVersion)   { $params.EngineVersion    = $EngineVersion }
        if ($EngineAction)    { $params.EngineAction     = $EngineAction }

        # Collect each configuration's structured result so the run can be summarized as a
        # single machine-readable object and, with -FailOnError, surface a non-zero exit code.
        $runResults = Get-ChildItem -LiteralPath $exportConfigDir -File -Filter "*.yml" | ForEach-Object {
            Start-DscRunner -FilePath $_.Fullname @params
        }

        $summaryArgs = @{ Result = $runResults }
        if ($ReportPath)  { $summaryArgs.ReportPath  = $ReportPath }
        if ($FailOnError) { $summaryArgs.FailOnError  = $true }

        return Merge-DscRunnerResult @summaryArgs

    }
    finally {
        if ($KeepTemporaryDirectory) {
            Write-Verbose "[Invoke-DscRunner] -KeepTemporaryDirectory was supplied; leaving any temporary directories in place."
        }
        else {
            # No-op for a caller-supplied local directory; deletes only what this run created
            # (e.g. a git clone).
            Remove-RunnerTemporaryDirectory -Path $DatumConfigurationPath
        }
    }
}
