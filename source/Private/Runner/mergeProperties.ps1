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

        # Key only exists in source, or one side is null: keep whichever value is set.
        if (-not $merge.ContainsKey($key) -or $null -eq $merge[$key]) {
            $result[$key] = $source[$key]
            continue
        }
        if ($null -eq $source[$key]) {
            $result[$key] = $merge[$key]
            continue
        }

        if ($source[$key] -is [System.Collections.IDictionary] -and $merge[$key] -is [System.Collections.IDictionary]) {
            # Both are hashtables: recurse.
            $result[$key] = Join-Properties -source ([hashtable]$source[$key]) -merge ([hashtable]$merge[$key])
        }
        elseif ($source[$key] -is [System.Collections.IList] -and $merge[$key] -is [System.Collections.IList]) {
            # Both are collections (object[] from PowerShell, List[Object] from YAML): combine them,
            # source items first, dropping duplicates. Hashtable items are compared by their
            # key-sorted JSON so key order does not matter.
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            $combined = [System.Collections.Generic.List[Object]]::new()
            foreach ($item in @($source[$key]) + @($merge[$key])) {
                $identity = if ($item -is [System.Collections.IDictionary]) {
                    Sort-Hashtable -HashTable $item | ConvertTo-Json -Compress -Depth 20
                } else {
                    ConvertTo-Json -InputObject $item -Compress -Depth 20
                }
                if ($seen.Add($identity)) {
                    $combined.Add($item)
                } else {
                    Write-Verbose "[Join-Properties] Duplicate found: $identity"
                }
            }
            $result[$key] = $combined.ToArray()
        }
        else {
            # Scalars (or mismatched shapes): the source value wins.
            if ($source[$key].GetType() -ne $merge[$key].GetType()) {
                Write-Warning "[Join-Properties] Type mismatch for key '$key'. Preferring source value."
            }
            $result[$key] = $source[$key]
        }

    }

    # Iterate over the merge hashtable
    foreach ($key in $merge.Keys) {

        # Does the key exist on both hashtables
        if (-not $source.ContainsKey($key)) {
            # No? Set the value from the merge
            if ($merge[$key] -is [System.Collections.IDictionary]) {
                # If it's a hashtable, call Join-Properties and recurse
                $result[$key] = Join-Properties -source @{} -merge ([hashtable]$merge[$key])
            } else {
                $result[$key] = $merge[$key]
            }
        }
        
    }

    return $result
}
