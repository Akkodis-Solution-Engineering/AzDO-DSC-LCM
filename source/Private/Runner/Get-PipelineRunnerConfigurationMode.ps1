<#
.SYNOPSIS
    Determines the Pipeline Runner Configuration Mode based on the provided Datum Configuration.

.DESCRIPTION
    The Get-PipelineRunnerConfigurationMode function calculates the Pipeline Runner Configuration Mode for a given Datum Configuration object. It supports both static modes (ApplyOnly, Audit, Enforce) and a Scheduled mode that allows for time-based configuration changes.

    Each ChangeWindow is evaluated in order. The first window whose time range AND optional day-of-week
    constraint both match the current UTC time takes effect. If windows overlap, the first match wins.

.PARAMETER DatumConfigurationMode
    The Datum Configuration object that contains the PipelineConfigurationMode property. This property can either be a static mode or a Scheduled mode with defined Change Windows.
    Example of DatumConfigurationMode:

    PipelineConfigurationMode:
        # The Pipeline Runner Configuration Mode can be one of the following: ApplyOnly, Audit, Enforce, Scheduled
        ConfigurationMode: Scheduled
        # Define a Change Window Array that specifies when the configuration can be applied.
        ChangeWindows:
            - StartTime: '20:00'       # Start of the change window. Time is in UTC.
              EndTime: '23:59'         # End of the change window. Time is in UTC.
              ConfigurationMode: Audit
            - StartTime: '00:00'
              EndTime: '02:00'
              ConfigurationMode: Enforce
              DaysOfWeek:             # Optional: restrict to specific days (UTC). Omit to apply every day.
                - Tuesday
                - Wednesday
                - Thursday

#>
function Get-PipelineRunnerConfigurationMode {
    param(
        [Parameter(Mandatory = $true)]
        [HashTable]$DatumConfigurationMode
    )

    Write-Verbose "[Get-PipelineRunnerConfigurationMode] Determining Pipeline Runner Configuration Mode for Datum Configuration: $DatumConfigurationMode"

    #
    # Calculate the Pipeline Runner Configuration Mode based on the Datum Configuration Mode

    if ($DatumConfigurationMode.ConfigurationMode -eq 'Scheduled') {

        $nowUTC = (Get-Date).ToUniversalTime()
        $CurrentTimeUTC = $nowUTC.ToString('HH:mm')
        $CurrentDayUTC  = $nowUTC.DayOfWeek.ToString()  # e.g. "Monday"

        $PipelineConfigurationMode = 'Audit' # Default to Audit if no windows match
        $isSet = $false

        foreach ($ChangeWindow in $DatumConfigurationMode.ChangeWindows) {

            # --- Time check ---
            if (-not ($CurrentTimeUTC -ge $ChangeWindow.StartTime -and $CurrentTimeUTC -lt $ChangeWindow.EndTime)) {
                continue
            }

            # --- Day-of-week check (optional constraint) ---
            $daysOfWeek = $ChangeWindow.DaysOfWeek
            if ($null -ne $daysOfWeek -and $daysOfWeek.Count -gt 0) {
                if ($daysOfWeek -inotcontains $CurrentDayUTC) {
                    Write-Verbose "[Get-PipelineRunnerConfigurationMode] Current day '$CurrentDayUTC' is not in the DaysOfWeek constraint [$($daysOfWeek -join ', ')] for window $($ChangeWindow.StartTime)-$($ChangeWindow.EndTime). Skipping."
                    continue
                }
            }

            # --- Overlap check: first matching window wins ---
            if ($isSet) {
                Write-Warning "[Get-PipelineRunnerConfigurationMode] Overlapping Change Windows detected in Datum Configuration PipelineConfigurationMode. The first matching window takes precedence."
                continue
            }

            $dayInfo = if ($null -ne $daysOfWeek -and $daysOfWeek.Count -gt 0) { " on [$($daysOfWeek -join ', ')]" } else { '' }
            Write-Host "[Get-PipelineRunnerConfigurationMode] Current time $CurrentTimeUTC ($CurrentDayUTC) is within Change Window: $($ChangeWindow.StartTime)-$($ChangeWindow.EndTime)$dayInfo. Setting Pipeline Runner Configuration Mode to $($ChangeWindow.ConfigurationMode)."

            $isSet = $true
            $PipelineConfigurationMode = $ChangeWindow.ConfigurationMode
        }

    } else {
        # For non-scheduled modes, set the Pipeline Runner Configuration Mode to the specified mode.
        $PipelineConfigurationMode = $DatumConfigurationMode.ConfigurationMode
    }

    return $PipelineConfigurationMode

}
