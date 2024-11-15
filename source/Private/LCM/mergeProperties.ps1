function Join-Properties {
    [CmdletBinding()]
    [Alias('mergeProperties')]
    param (
        [HashTable] $source,
        [HashTable] $merge
    )

    # Define a temporary hashtable that contains the source
    $result = @{}


    # If both source and merge ar null, return null.
    if ((-not($source)) -and (-not($merge))) {
        return $null
    }

    # If the source hashtable is null, return the merge hashtable.
    if (-not $source) {
        return $merge
    }

    # If the merge hashtable is null, return the source hashtable.
    if (-not $merge) {
        return $source
    }

    # Iterate over the source hashtable
    foreach ($key in $source.Keys) {

        # Does the key exist on both hashtables?
        if ($merge.ContainsKey($key)) {

            # Are they the same type? If not, preference the source and log a warning.
            if ($source[$key].GetType().Name -ne $merge[$key].GetType().Name) {
                Write-Warning "[Join-Properties] Type mismatch for key '$key'. Preferring source value."
                $result[$key] = $source."$key"
            }

            # Is the key a hashtable?
            if ($source[$key] -is [hashtable] -and $merge[$key] -is [hashtable]) {
                # Call Join-Properties and recurse
                $result[$key] = Join-Properties -source $source[$key] -merge $merge[$key]
            }

            # If the key is a collection (e.g., array)
            elseif (($source[$key] -is [System.Collections.ICollection]) -and ($merge[$key] -is [System.Collections.ICollection])) {
                # Combine the collections
                $result[$key] += $source[$key] + $merge[$key]
                # Please note that further work is required to remove duplicate values.
            }

            # If the key is a string array
            elseif ($source[$key] -is [string[]] -and $merge[$key] -is [string[]]) {
                # Combine the string arrays
                $result[$key] = $source[$key] + $merge[$key] | Select-Object -Unique
            } else {
                # Set the value from the source
                $result[$key] = $source[$key]
            }

        } else {
            # Key only exists in source
            $result[$key] = $source[$key]
        }

    }

    # Iterate over the merge hashtable
    foreach ($key in $merge.Keys) {

        # Does the key exist on both hashtables
        if (-not $source.ContainsKey($key)) {
            # No? Set the value from the merge
            if ($merge[$key] -is [hashtable]) {
                # If it's a hashtable, call Join-Properties and recurse
                $result[$key] = Join-Properties -source @{} -merge $merge[$key]
            } else {
                $result[$key] = $merge[$key]
            }
        }
        
    }

    return $result
}
