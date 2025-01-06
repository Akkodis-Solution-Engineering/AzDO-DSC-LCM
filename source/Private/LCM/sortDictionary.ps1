Function Sort-Hashtable {
    [CmdletBinding()]
    [Alias('sortDictionary')]
    Param (
        [Parameter(Mandatory=$true)]
        [HashTable]
        $HashTable
    )

    if ($null -eq $HashTable) {
        return @{}
    }

    $OrderedHashTable = [Ordered]@{}
    foreach ($key in ($HashTable.Keys | Sort-Object)) {
        # If the value is a hashtable, recurse
        if ($HashTable[$key] -is [hashtable]) {
            $OrderedHashTable[$key] = Sort-Hashtable -HashTable $HashTable[$key]
            continue
        }
        # If the value is an array of hashtables, recurse
        if ($HashTable[$key] -is [array]) {
            $OrderedHashTable[$key] = $HashTable[$key] | ForEach-Object { Sort-Hashtable -HashTable $_ }
            continue
        }
        $OrderedHashTable[$key] = $HashTable[$key]
    }

    $OrderedHashTable

}