<#
.SYNOPSIS
    Validates the Datum Configuration to ensure it meets the required standards.

.DESCRIPTION
    The Test-DatumConfiguration function validates the Datum Configuration object to ensure it contains the necessary properties and that the versioning is correct. 
    It checks for the presence and validity of the PipelineConfigurationMode property (including time-based
    Scheduled ChangeWindows) and the PipelineRunnerSettings property, validates the versioning of the Datum
    Configuration, and ensures that the versions are within the acceptable range.

.PARAMETER Datum
    The Datum Configuration object that needs to be validated. This parameter is mandatory.

.EXAMPLE
    $datumConfig = Get-DatumConfiguration
    Test-DatumConfiguration -Datum $datumConfig

    This example retrieves a Datum Configuration object and validates it using the Test-DatumConfiguration function.

.NOTES
    The function throws an error if the Datum Configuration is invalid or if any of the version checks fail. It also provides verbose output for each validation step and a warning if the Datum Configuration version is two or more minor versions behind the current PSDesiredStateConfiguration version.

#>
function Test-DatumConfiguration {   
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Object]
        $Datum
    )

    Write-Verbose "[Test-DatumConfiguration] Validating the Datum Configuration."

    #
    # Validate the PipelineConfigurationMode Configuration (static or time-based Scheduled enforcement)
    #

    $allowedChangeWindowConfigurationModes = @('ApplyOnly', 'Audit', 'Enforce')
    $allowedConfigurationModes = @('ApplyOnly', 'Audit', 'Enforce', 'Scheduled')

    if ($null -eq $Datum.__Definition.PipelineConfigurationMode) {
        throw "[Test-DatumConfiguration] The Datum Configuration does not contain the PipelineConfigurationMode property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the PipelineConfigurationMode contains the required properties.
    if (-not $Datum.__Definition.PipelineConfigurationMode.ContainsKey('ConfigurationMode')) {
        throw "[Test-DatumConfiguration] The Datum Configuration PipelineConfigurationMode does not contain the ConfigurationMode property. The Datum Configuration is invalid and cannot be processed."
    }

    # Permitted values for ConfigurationMode are: ApplyOnly, Audit, Enforce, Scheduled
    if ($allowedConfigurationModes -notcontains $Datum.__Definition.PipelineConfigurationMode.ConfigurationMode) {
        throw "[Test-DatumConfiguration] The Datum Configuration PipelineConfigurationMode ConfigurationMode property is not one of the allowed values: $($allowedConfigurationModes -join ', '). The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the ConfigurationMode is one of the allowed values.
    if (-not $Datum.__Definition.PipelineConfigurationMode.ContainsKey('ChangeWindows')) {
        throw "[Test-DatumConfiguration] The Datum Configuration PipelineConfigurationMode does not contain the ChangeWindows property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate the properties of the ChangeWindows array.
    ForEach ($ChangeWindow in $Datum.__Definition.PipelineConfigurationMode.ChangeWindows) {
        if (-not $ChangeWindow.ContainsKey('StartTime') -or -not $ChangeWindow.ContainsKey('EndTime') -or -not $ChangeWindow.ContainsKey('ConfigurationMode')) {
            throw "[Test-DatumConfiguration] Each ChangeWindow in the Datum Configuration PipelineConfigurationMode must contain StartTime, EndTime, and ConfigurationMode properties. The Datum Configuration is invalid and cannot be processed."
        }
        # Permitted values for ConfigurationMode in ChangeWindows are: ApplyOnly, Audit, Enforce
        if ($allowedChangeWindowConfigurationModes -notcontains $ChangeWindow.ConfigurationMode) {
            throw "[Test-DatumConfiguration] The ConfigurationMode property in each ChangeWindow of the Datum Configuration PipelineConfigurationMode must be one of the allowed values: $($allowedChangeWindowConfigurationModes -join ', '). The Datum Configuration is invalid and cannot be processed."
        }
        # Validate that Start and End are time strings are in the correct 24-hour format.
        if (-not ($ChangeWindow.StartTime -match '^\d{2}:\d{2}$') -or -not ($ChangeWindow.EndTime -match '^\d{2}:\d{2}$')) {
            throw "[Test-DatumConfiguration] The StartTime and EndTime properties in the ChangeWindow must be in the format HH:mm (24-hour format). The Datum Configuration is invalid and cannot be processed."
        }
        # Ensure that the StartTime and EndTime are in 24-hour format.
        try {
            $null = [datetime]::ParseExact($ChangeWindow.StartTime, "HH:mm", $null)
            $null = [datetime]::ParseExact($ChangeWindow.EndTime, "HH:mm", $null)
        } catch {
            throw "[Test-DatumConfiguration] The StartTime and EndTime properties in the ChangeWindow must be valid time strings in the format HH:mm (24-hour format). The Datum Configuration is invalid and cannot be processed."
        }
        # Validate DaysOfWeek if the optional property is present.
        $validDays = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
        if ($null -ne $ChangeWindow.DaysOfWeek -and $ChangeWindow.DaysOfWeek.Count -gt 0) {
            foreach ($day in $ChangeWindow.DaysOfWeek) {
                if ($validDays -inotcontains $day) {
                    throw "[Test-DatumConfiguration] Invalid DaysOfWeek value '$day' in ChangeWindow. Valid values are: $($validDays -join ', '). The Datum Configuration is invalid and cannot be processed."
                }
            }
        }
    }

    # Ensure that ChangeWindows contains at least one entry if ConfigurationMode is 'Scheduled'.
    if ($Datum.__Definition.PipelineConfigurationMode.ConfigurationMode -eq 'Scheduled' -and
        -not $Datum.__Definition.PipelineConfigurationMode.ChangeWindows.Count -ne 0) {
        throw "[Test-DatumConfiguration] The Datum Configuration PipelineConfigurationMode ChangeWindows property must contain at least one entry when the ConfigurationMode is 'Scheduled'. The Datum Configuration is invalid and cannot be processed."
    }

    #
    # Validate that the Datum Configuration meets the requirements for the Datum Configuration.
    if ($null -eq $Datum.__Definition.PipelineRunnerSettings) {
        throw "[Test-DatumConfiguration] The Datum Configuration does not contain the PipelineRunnerSettings property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the Datum Configuration Versioning is the correct version. If not, throw an error.

    # Get the Datum Configuration Version
    $runnerConfig = @{
        DatumConfigurationVersion   = $Datum.__Definition.PipelineRunnerSettings.ConfigurationVersion -as [Version]
        PipelineRunnerVersion              = $Datum.__Definition.PipelineRunnerSettings.PipelineRunnerVersion -as [Version]
        YAMLConfigurationMinimumVersion = $ModuleConfigurationData.YAMLConfigurationMinimumVersion -as [Version]
        YAMLConfigurationMaximumVersion = $ModuleConfigurationData.YAMLConfigurationMaximumVersion -as [Version]
    }

    $CurrentPSDesiredStateConfigurationVersion = (Get-Module PSDesiredStateConfiguration | Select-Object -First 1).Version
    $CurrentPipelineRunnerVersion = (Get-Module DSC.PipelineRunner.Akkodis | Select-Object -First 1).Version

    Write-Verbose "[Test-DatumConfiguration] Datum Configuration Version: $($runnerConfig.DatumConfigurationVersion)"

    # Confirm that all the Datum Configuration Versions have been safely typecasted to the [Version] type.
    foreach ($runnerConfigKey in $runnerConfig.Keys) {
        Write-Verbose "[Test-DatumConfiguration] Validating Datum Configuration Version for $runnerConfigKey."
        if ($null -eq $runnerConfig[$runnerConfigKey]) {
            throw "[Test-DatumConfiguration] The Datum Configuration Version for $runnerConfigKey is not a valid version. The Datum Configuration is invalid and cannot be processed. Please ensure that the Datum Configuration Version is a valid version."
        }
    }

    #
    # Validate the Datum Configuration Versioning
    #

    $supportedConfigurationMaxMajorVersion = $runnerConfig.YAMLConfigurationMaximumVersion.Major
    $supportedConfigurationMaxMinorVersion = $runnerConfig.YAMLConfigurationMaximumVersion.Minor
    $supportedConfigurationMinMajorVersion = $runnerConfig.YAMLConfigurationMinimumVersion.Major
    $supportedConfigurationMinMinorVersion = $runnerConfig.YAMLConfigurationMinimumVersion.Minor

    $datumConfigurationMajorVersion = $runnerConfig.DatumConfigurationVersion.Major
    $datumConfigurationMinorVersion = $runnerConfig.DatumConfigurationVersion.Minor

    # Combine the Major and Minor versions as a decimal number to compare the versions.
    $maxSupportedVersion = [decimal]::Parse("$supportedConfigurationMaxMajorVersion.$supportedConfigurationMaxMinorVersion")
    $minSupportedVersion = [decimal]::Parse("$supportedConfigurationMinMajorVersion.$supportedConfigurationMinMinorVersion")

    $currentVersion = [decimal]::Parse("$datumConfigurationMajorVersion.$datumConfigurationMinorVersion")
    
    # Throw an error if the Datum Configuration Version is outside the valid range of the Datum Configuration Versions.
    if (($currentVersion -lt $minSupportedVersion) -or ($currentVersion -gt $maxSupportedVersion)) {
        throw "[Test-DatumConfiguration] The Datum Configuration Version $($runnerConfig.DatumConfigurationVersion) is outside the valid range ($($runnerConfig.YAMLConfigurationMinimumVersion) to $($runnerConfig.YAMLConfigurationMaximumVersion)). The Datum Configuration is invalid and cannot be processed."
    }

    # Check if the Datum Configuration Version is two or more minor versions behind the current PSDesiredStateConfiguration version.
    # If it is, write a warning.
    if ($currentVersion -ge ($maxSupportedVersion - 0.2)) {
        Write-Warning "[Test-DatumConfiguration] The Datum Configuration Version $($runnerConfig.DatumConfigurationVersion) is two or more minor versions behind the current PSDesiredStateConfiguration version $($runnerConfig.CurrentPSDesiredStateConfigurationVersion). Consider updating to a more recent version."
    }

    #
    # Validate the PSDesiredStateConfiguration Versions
    #

    $PSDesiredStateConfigurationMinimumVersion = $ModuleConfigurationData.PSDesiredStateConfigurationMinimumVersion -as [Version]
    $PSDesiredStateConfigurationMaximumVersion = $ModuleConfigurationData.PSDesiredStateConfigurationMaximumVersion -as [Version]

    # Ensure that the Module PSDesiredStateConfiguration Version is within the valid range of the Datum Configuration Versions.
    if ($CurrentPSDesiredStateConfigurationVersion -lt $PSDesiredStateConfigurationMinimumVersion -or 
        $CurrentPSDesiredStateConfigurationVersion -gt $PSDesiredStateConfigurationMaximumVersion) {
        throw "[Test-DatumConfiguration] The PSDesiredStateConfiguration Version $($CurrentPSDesiredStateConfigurationVersion) is outside the valid range ($($PSDesiredStateConfigurationMinimumVersion) to $($PSDesiredStateConfigurationMaximumVersion)). The Datum Configuration is invalid and cannot be processed."
    }

    #
    # Validate the DSC.PipelineRunner.Akkodis Versions
    #

    # Read the configured bounds from ModuleConfigurationData. Previously this check
    # compared $runnerConfig.PipelineRunnerMinimumVersion / .CurrentPipelineRunnerVersion,
    # neither of which was ever populated, so it was a permanent no-op ($x -lt $null is
    # always $false). Use the real installed version and the configured bounds, and warn
    # (rather than silently pass) when a bound cannot be determined.
    $PipelineRunnerMinimumVersion = $ModuleConfigurationData.DSCResourceMinimumVersion -as [Version]
    $PipelineRunnerMaximumVersion = $ModuleConfigurationData.DSCResourceMaximumVersion -as [Version]

    if (($null -eq $PipelineRunnerMinimumVersion) -or ($null -eq $PipelineRunnerMaximumVersion)) {
        Write-Warning "[Test-DatumConfiguration] The DSC.PipelineRunner.Akkodis minimum/maximum version bounds are not configured; skipping the DSC.PipelineRunner.Akkodis version check."
    }
    elseif ($null -eq $CurrentPipelineRunnerVersion) {
        Write-Warning "[Test-DatumConfiguration] The installed DSC.PipelineRunner.Akkodis module version could not be determined; skipping the DSC.PipelineRunner.Akkodis version check."
    }
    elseif ($CurrentPipelineRunnerVersion -lt $PipelineRunnerMinimumVersion -or
            $CurrentPipelineRunnerVersion -gt $PipelineRunnerMaximumVersion) {
        throw "[Test-DatumConfiguration] The DSC.PipelineRunner.Akkodis Version $CurrentPipelineRunnerVersion is outside the valid range ($PipelineRunnerMinimumVersion to $PipelineRunnerMaximumVersion). The Datum Configuration is invalid and cannot be processed."
    }

}
