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
    if (($null -eq $source) -and ($null -eq $merge)) {
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
            elseif ($source[$key].GetType().BaseType.Name -eq 'Array') {

                # Combine the collections
                $combined = $source[$key] + $merge[$key]
                # Attempt to remove duplicates
                
                # If the values within the collection are an array of strings, we can use Select-Object -Unique
                $array, $collection = $combined.Where({ $_.GetType().Name -in 'String','Int32','Boolean' }, 'Split')
             
                # Iterate through the collection and remove duplicates
                $arrayList = [System.Collections.Generic.List[Object]]::new()

                # If the values within the collection are not strings, we need to use a different method
                ForEach ($item in $collection) {
                    
                    # Create a custom hashtable that stores an ordered hashtable and a compressed version of the ordered hashtable.
                    $ht = @{
                        Value = Sort-Hashtable $item
                        compressed = $null
                    }

                    $compressed = $ht.Value | ConvertTo-Json -Compress
                    # Check for duplicates within the arraylist
                    
                    $exists = $arrayList | Where-Object { $_.compressed -eq $compressed }

                    # If the item already exists, skip it
                    if (@($exists).Count -ne 0) {
                        write-verbose "[Join-Properties] Duplicate found: $compressed"
                        $arrayList.Add($ht)
                    }

                }

                if ($arrayList.Count -eq 0) {
                    $result[$key] = $array | Select-Object -Unique
                } else {
                    $result[$key] = ($array | Select-Object -Unique) + $arrayList.Value
                }

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
