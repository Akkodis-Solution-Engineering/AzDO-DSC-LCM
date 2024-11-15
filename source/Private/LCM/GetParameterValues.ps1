function Get-ParameterValues {
    [CmdletBinding()]
    [Alias('GetParameterValues')]
    param (
        [hashtable] $Source
    )

    $values = @{}
    foreach ($key in $Source.Keys) {
        $values.Add($key, (Get-Variable -Name $Source[$key] -ValueOnly))
    }

    return $values
}