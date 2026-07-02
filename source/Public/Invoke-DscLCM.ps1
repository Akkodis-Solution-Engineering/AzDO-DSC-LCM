<#
.SYNOPSIS
Invokes the Local Configuration Manager (LCM) against a Datum configuration source, independent of any specific DSC resource module.

.DESCRIPTION
The Invoke-DscLCM function compiles a Datum configuration source, validates it, resolves the LCM Configuration Mode, and invokes Start-LCM against every exported configuration file.

Unlike Invoke-AZDoLCM, this function performs no authentication of its own. If the resources referenced by your configuration's `type:` fields require an authenticated connection (for example, DSC resources that call out to a remote service), authenticate using that resource module's own mechanism before calling this function.

.PARAMETER exportConfigDir
Specifies the directory where configuration files are exported by Datum. This parameter is mandatory and must be a valid directory path.

.PARAMETER ConfigurationSourcePath
Specifies the URL or directory path for the configuration source. This parameter is mandatory.

.PARAMETER ConfigurationMode
Specifies the Local Configuration Manager (LCM) mode to use. Valid values are 'ApplyOnly', 'Audit', and 'Enforce'. This parameter is optional; if not provided, the mode will be determined from the Datum configuration.

.PARAMETER ReportPath
Specifies the path to the report file. This parameter is optional and must be a valid directory path.

.PARAMETER ContinueOnError
When specified, a resource Set failure does not halt the LCM run. Instead, resources that directly or transitively depend on the failed resource are automatically skipped; all others continue normally.

.EXAMPLE
Invoke-DscLCM -exportConfigDir "C:\Configs" -ConfigurationSourcePath "https://repo.url" -ConfigurationMode "Audit"

This example compiles and runs the configuration in 'Audit' mode.

#>

function Invoke-DscLCM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [String]$exportConfigDir,

        [Parameter(Mandatory)]
        [String]$ConfigurationSourcePath,

        [Parameter()]
        [ValidateSet("ApplyOnly", "Audit", "Enforce")]
        [AllowEmptyString()]
        [String]$ConfigurationMode,

        [Parameter()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [String]$ReportPath,

        [Parameter()]
        [Switch]$ContinueOnError
    )

    # Set the Error Action Preference
    $ErrorActionPreference = "Stop"

    #
    # Clone the Datum Configuration from the Configuration URL

    # Test ConfigurationSourcePath if it is a URL. If URL attempt to clone.
    if ($ConfigurationSourcePath -match '^(http|https):\/\/') {
        # Cone from URL
        $DatumConfigurationPath = Clone-Repository -DatumURLConfig $ConfigurationSourcePath
    }
    # Test if ConfigurationSourcePath is a directory path that exists.
    elseif (Test-Path -Path $ConfigurationSourcePath -PathType Container) {
        $DatumConfigurationPath = $ConfigurationSourcePath
    }
    # Else. Throw an error for bad data.
    else {
        throw "[Invoke-DscLCM] Invalid ConfigurationSourcePath: $ConfigurationSourcePath"
    }

    #
    # Compile the Datum Configuration
    Build-DatumConfiguration -OutputPath $exportConfigDir -ConfigurationPath $DatumConfigurationPath

    #
    # Read and validate the Datum Configuration

    $DatumConfiguration = Get-Content -Path (Join-Path $DatumConfigurationPath 'datum.yml') | ConvertFrom-Yaml
    Test-DatumConfiguration -Datum @{ '__Definition' = $DatumConfiguration }

    #
    # Determine the LCM Configuration Mode

    # If the ConfigurationMode parameter is provided, use it. Otherwise, determine the mode from the Datum Configuration.
    if (-not $ConfigurationMode) {
        $ConfigurationMode = Get-LCMConfigurationMode -DatumConfigurationMode $DatumConfiguration.LCMConfigurationMode
    }

    #
    # Invoke the Resources

    # Create a hashtable to store the parameters
    $params = @{
        ConfigurationMode = $ConfigurationMode
        DSCCompositeResourcePath = Join-Path $DatumConfigurationPath 'CompositeResources'
    }

    # If the ReportPath is provided, add it to the parameters
    if ($ReportPath) {
        $params.ReportPath = $ReportPath
    }

    # Pass ContinueOnError through to each LCM run
    if ($ContinueOnError) {
        $params.ContinueOnError = $true
    }

    Get-ChildItem -LiteralPath $exportConfigDir -File -Filter "*.yml" | ForEach-Object {
        Start-LCM -FilePath $_.Fullname @params
    }

}
