Function Sort-Hashtable {
    [CmdletBinding()]
    [Alias('sortDictionary')]
    Param (
        [Parameter(Mandatory=$true)]
        [System.Collections.IDictionary]
        $HashTable
    )

    if ($null -eq $HashTable) {
        return @{}
    }

    $OrderedHashTable = [Ordered]@{}
    foreach ($key in ($HashTable.Keys | Sort-Object)) {
        # If the value is a hashtable, recurse
        if ($HashTable[$key] -is [System.Collections.IDictionary]) {
            $OrderedHashTable[$key] = Sort-Hashtable -HashTable $HashTable[$key]
            continue
        }
        # If the value is a collection, recurse into its hashtable items and keep the rest as-is.
        if ($HashTable[$key] -is [System.Collections.IList]) {
            $OrderedHashTable[$key] = @($HashTable[$key] | ForEach-Object {
                if ($_ -is [System.Collections.IDictionary]) { Sort-Hashtable -HashTable $_ } else { $_ }
            })
            continue
        }
        $OrderedHashTable[$key] = $HashTable[$key]
    }

    $OrderedHashTable

}