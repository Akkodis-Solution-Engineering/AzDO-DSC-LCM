function Get-HoursDifference {
    param (
        [string]$StartTime,
        [string]$EndTime
    )

    # Convert the time strings to DateTime objects for today's date
    $date1 = [datetime]::ParseExact($StartTime, "HH:mm", $null)
    $date2 = [datetime]::ParseExact($EndTime, "HH:mm", $null)

    # Calculate the time difference
    $timeDifference = $date2 - $date1

    # If the time difference is negative, add 24 hours
    if ($timeDifference.TotalHours -lt 0) {
        $timeDifference = $timeDifference + [timespan]::FromHours(24)
    }

    # Output the total hours transpired
    return $timeDifference.TotalHours
}
