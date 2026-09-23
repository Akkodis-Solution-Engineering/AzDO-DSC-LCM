<#
.SYNOPSIS
Invokes the DSC pipeline runner against an Azure DevOps-authenticated configuration source.

.DESCRIPTION
The Invoke-DscPipelineRunner function is the Azure DevOps-flavoured entry point: it supports
Managed Identity and Personal Access Token (PAT) authentication, authenticates to Azure DevOps,
and then delegates configuration compilation and resource invocation to the provider-agnostic
Invoke-DscRunner.

This function requires the AzureDevOpsDsc.Common module to be installed. If your configuration
does not need Azure DevOps authentication, call Invoke-DscRunner directly instead.

.PARAMETER AzureDevopsOrganizationName
Specifies the name of the Azure DevOps organization. This parameter is mandatory.

.PARAMETER exportConfigDir
Specifies the directory where configuration files are exported by Datum. This parameter is mandatory and must be a valid directory path.

.PARAMETER ConfigurationSourcePath
Specifies the URL or directory path for the configuration source. This parameter is mandatory.

.PARAMETER ConfigurationRevision
Optional branch, tag, or commit to pin a remote (git) configuration source to. See
Invoke-DscRunner's -ConfigurationRevision.

.PARAMETER JITToken
Specifies the Just-In-Time (JIT) access token. This parameter is mandatory.

.PARAMETER ConfigurationMode
Specifies the pipeline runner mode to use. Valid values are 'ApplyOnly', 'Audit', and 'Enforce'. This parameter is optional; if not provided, the mode will be determined from the Datum configuration.

.PARAMETER AuthenticationType
Specifies the authentication type to use. Valid values are 'ManagedIdentity' and 'PAT'. The default value is 'ManagedIdentity'.

.PARAMETER PATToken
Specifies the Personal Access Token (PAT). This parameter is mandatory when AuthenticationType is set to 'PAT' and must be a valid 52-character alphanumeric string.

.PARAMETER ReportPath
Specifies the path to the report file. This parameter is optional and must be a valid directory path.

.PARAMETER ContinueOnError
When specified, a resource Set failure does not halt the run. Instead, resources that directly
or transitively depend on the failed resource are automatically skipped; all others continue normally.

.PARAMETER Engine
Execution engine action (Actions/Engine/<Engine>.ps1). See Invoke-DscRunner's -Engine.

.PARAMETER EngineVersion
Optional resource version hint that biases 'Auto' engine selection by major version.

.PARAMETER FailOnError
Opt-in switch. When the aggregated run status is Failed or Aborted, sets the process exit code to 1.

.PARAMETER KeepTemporaryDirectory
Leave any temporary directory this function created (a git clone) on disk after the run
instead of deleting it.

.EXAMPLE
Invoke-DscPipelineRunner -AzureDevopsOrganizationName "MyOrg" -exportConfigDir "C:\Configs" -ConfigurationSourcePath "https://repo.url" -ConfigurationMode "Enforce" -AuthenticationType "PAT" -PATToken "pat_token"

This example invokes the DSC pipeline runner using a PAT for Azure DevOps authentication.

.NOTES
Ensure that the environment variable AZDODSC_CACHE_DIRECTORY is set before running this function
if any of the resources referenced by the configuration read it at execution time — the runner
itself no longer requires it (see Resolve-CacheDirectory / PIPELINERUNNER_CACHE_DIRECTORY).

#>
function Invoke-DscPipelineRunner {
    [CmdletBinding(defaultParameterSetName='Default')]
    param(
        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$AzureDevopsOrganizationName,

        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [String]$exportConfigDir,

        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$ConfigurationSourcePath,

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='PAT')]
        [String]$ConfigurationRevision,

        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$JITToken,

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='PAT')]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")]
        [AllowEmptyString()]
        [String]$ConfigurationMode,

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='PAT')]
        [ValidateSet('ManagedIdentity', 'PAT')]
        [String]$AuthenticationType='ManagedIdentity',

        [Parameter(Mandatory, ParameterSetName='PAT')]
        [ValidateScript({$_ -match '^[a-zA-Z0-9]{52}$'})]
        [String]$PATToken,

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
        [Switch]$FailOnError,

        [Parameter()]
        [Switch]$KeepTemporaryDirectory
    )

    # Set the Error Action Preference
    $ErrorActionPreference = "Stop"

    #
    # Ensure the Azure DevOps-specific auth dependency is available before doing anything else.

    try {
        Import-Module -Name 'AzureDevOpsDsc.Common' -ErrorAction Stop
    } catch {
        throw "[Invoke-DscPipelineRunner] Required module 'AzureDevOpsDsc.Common' is not available. Install it via 'Install-Module AzureDevOpsDsc.Common' before calling Invoke-DscPipelineRunner, or call Invoke-DscRunner directly if Azure DevOps authentication is not required. Underlying error: $($_.Exception.Message)"
    }

    #
    # Determine the Authentication Type and create the Authentication Provider

    if ($AuthenticationType -eq 'PAT') {
        New-AzDoAuthenticationProvider -OrganizationName $AzureDevopsOrganizationName -PersonalAccessToken $PATToken
    } elseif ($AuthenticationType -eq 'ManagedIdentity') {
        New-AzDoAuthenticationProvider -OrganizationName $AzureDevopsOrganizationName -useManagedIdentity
    }

    #
    # Delegate configuration compilation and resource invocation to the generic entry point.

    $params = @{
        exportConfigDir         = $exportConfigDir
        ConfigurationSourcePath = $ConfigurationSourcePath
        Engine                  = $Engine
    }

    if ($ConfigurationRevision)  { $params.ConfigurationRevision  = $ConfigurationRevision }
    if ($ConfigurationMode)      { $params.ConfigurationMode      = $ConfigurationMode }
    if ($ReportPath)             { $params.ReportPath             = $ReportPath }
    if ($ContinueOnError)        { $params.ContinueOnError        = $true }
    if ($EngineVersion)          { $params.EngineVersion          = $EngineVersion }
    if ($FailOnError)            { $params.FailOnError            = $true }
    if ($KeepTemporaryDirectory) { $params.KeepTemporaryDirectory = $true }

    # The module's `git` wrapper (source/Private/DatumHelper/git.ps1) reads $JITToken as a
    # bare variable, resolving through the scope chain to this module's script scope when not
    # shadowed locally. Setting it here (rather than requiring every caller to route through
    # the generic Source/Connect action pair) is what lets Clone-Repository authenticate a
    # private ConfigurationSourcePath using the JITToken this function already requires.
    # Cleared in the finally block so it does not linger for an unrelated later call.
    $script:JITToken = $JITToken

    try {
        Invoke-DscRunner @params
    }
    finally {
        $script:JITToken = $null
    }

}
