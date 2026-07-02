<#
.SYNOPSIS
Invokes the Azure DevOps Lifecycle Management (LCM) process using specified configurations and authentication methods.

.DESCRIPTION
The Invoke-AZDoLCM function is designed to manage the lifecycle of Azure DevOps configurations. It supports advanced function features similar to cmdlets and allows for different authentication methods, including Managed Identity and Personal Access Token (PAT). It authenticates to Azure DevOps and then delegates configuration compilation and resource invocation to Invoke-DscLCM.

This function requires the AzureDevOpsDsc.Common module to be installed. If your configuration does not need Azure DevOps authentication, call Invoke-DscLCM directly instead.

.PARAMETER AzureDevopsOrganizationName
Specifies the name of the Azure DevOps organization. This parameter is mandatory.

.PARAMETER exportConfigDir
Specifies the directory where configuration files are exported by Datum. This parameter is mandatory and must be a valid directory path.

.PARAMETER ConfigurationSourcePath
Specifies the URL or directory path for the configuration source. This parameter is mandatory.

.PARAMETER JITToken
Specifies the Just-In-Time (JIT) access token. This parameter is mandatory.

.PARAMETER ConfigurationMode
Specifies the Local Configuration Manager (LCM) mode to use. Valid values are 'ApplyOnly', 'Audit', and 'Enforce'. This parameter is optional; if not provided, the mode will be determined from the Datum configuration.

.PARAMETER AuthenticationType
Specifies the authentication type to use. Valid values are 'ManagedIdentity' and 'PAT'. The default value is 'ManagedIdentity'.

.PARAMETER PATToken
Specifies the Personal Access Token (PAT). This parameter is mandatory when AuthenticationType is set to 'PAT' and must be a valid 52-character alphanumeric string.

.PARAMETER ReportPath
Specifies the path to the report file. This parameter is optional and must be a valid file path.

.EXAMPLE
Invoke-AZDoLCM -AzureDevopsOrganizationName "MyOrg" -exportConfigDir "C:\Configs" -ConfigurationSourcePath "https://repo.url" -JITToken "token" -Mode "Set" -AuthenticationType "PAT" -PATToken "pat_token"

This example invokes the Azure DevOps LCM process using a PAT for authentication.

.NOTES
Ensure that the environment variable AZDODSC_CACHE_DIRECTORY is set before running this function. The function will throw an error if this environment variable is not set.

#>

function Invoke-AzDoLCM {
    # Utilizes the CmdletBinding attribute to enable advanced function features similar to cmdlets.
    [CmdletBinding(defaultParameterSetName='Default')]
    param(
        # Declares a mandatory parameter that specifies the name of the Azure DevOps organization.
        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$AzureDevopsOrganizationName,

        # Declares a mandatory parameter that specifies the directory where configuration files are exported by datum to:
        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [String]$exportConfigDir,

        # Declares a mandatory parameter that specifies the URL for the configuration.
        # This can be a directory path of a URL
        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$ConfigurationSourcePath,

        # Declares a mandatory parameter named JITToken which must be provided when the function is called.
        # This parameter expects a string value, typically representing a "Just-In-Time" access token.
        [Parameter(Mandatory, ParameterSetName='Default')]
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [String]$JITToken,

        # Declares an optional parameter with a ValidateSet attribute to restrict the value to either 'Test' or 'Set'.
        # The default value for this parameter is 'Set'.
        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='PAT')]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")]
        [AllowEmptyString()]
        [String]$ConfigurationMode,

        # Declare the AuthenticationType parameter with a ValidateSet attribute to restrict the value to 'ManagedIdentity' or 'PAT'.
        # The default value for this parameter is 'ManagedIdentity'.
        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='PAT')]
        [ValidateSet('ManagedIdentity', 'PAT')]
        [String]$AuthenticationType='ManagedIdentity',

        # Declare the PATToken parameter with a ValidateScript attribute to ensure the provided value is a valid Personal Access Token.
        # This parameter is mandatory when the AuthenticationType parameter is set to 'PAT'.
        [Parameter(Mandatory, ParameterSetName='PAT')]
        [ValidateScript({$_ -match '^[a-zA-Z0-9]{52}$'})]
        [String]$PATToken,

        # The following commented-out parameters could be used to specify a report path.
        # It includes a validation script to ensure the provided path points to a file (leaf) and not a directory.
        [Parameter()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [String]$ReportPath,

        # When specified, a resource Set failure does not halt the LCM run. Instead, resources that directly
        # or transitively depend on the failed resource are automatically skipped; all others continue normally.
        [Parameter()]
        [Switch]$ContinueOnError

    )

    # Set the Error Action Preference
    $ErrorActionPreference = "Stop"

    #
    # Test to make sure that the Enviroment Variable is Set.
    # The AzureDevOpsDsc resources read this at execution time; the generic Invoke-DscLCM
    # engine has no use for it, so this check lives here rather than in Invoke-DscLCM.

    if (-not $ENV:AZDODSC_CACHE_DIRECTORY) {
        throw "The Environment Variable AZDODSC_CACHE_DIRECTORY is not set. Please set the environment variable before running this script."
    }

    #
    # Ensure the Azure DevOps-specific auth dependency is available before doing anything else.

    try {
        Import-Module -Name 'AzureDevOpsDsc.Common' -ErrorAction Stop
    } catch {
        throw "[Invoke-AZDoLCM] Required module 'AzureDevOpsDsc.Common' is not available. Install it via 'Install-Module AzureDevOpsDsc.Common' before calling Invoke-AZDoLCM, or call Invoke-DscLCM directly if Azure DevOps authentication is not required. Underlying error: $($_.Exception.Message)"
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
    }

    if ($ConfigurationMode) {
        $params.ConfigurationMode = $ConfigurationMode
    }

    if ($ReportPath) {
        $params.ReportPath = $ReportPath
    }

    if ($ContinueOnError) {
        $params.ContinueOnError = $true
    }

    Invoke-DscLCM @params

}