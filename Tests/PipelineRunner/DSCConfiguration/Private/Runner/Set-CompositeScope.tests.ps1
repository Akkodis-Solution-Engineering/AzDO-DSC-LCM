Describe "Set-CompositeScope Function Tests" -Tag Unit, PipelineRunner, Configuration {

    BeforeAll {

        # Load the functions to test
        . (Get-FunctionPath 'Set-CompositeScope.ps1').FullName
        . (Get-FunctionPath 'Test-RunnerReservedVariableName.ps1').FullName

        # Property expansion is covered by its own tests. Here it resolves a single
        # "<from:Name>" marker against the current $parameters, which is enough to show a layer
        # is resolved in the scope built so far.
        function Expand-Parameters { param($InputHashTable) $InputHashTable }
        function Expand-HashTable {
            param($InputHashTable)
            $out = @{}
            foreach ($key in $InputHashTable.Keys) {
                $value = $InputHashTable[$key]
                if ($value -is [string] -and $value -match '^<from:(?<name>.+)>$') { $value = $parameters[$Matches.name] }
                $out[$key] = $value
            }
            $out
        }
    }

    BeforeEach {
        $parameters = @{}
        $variables  = @{}
        $script:compositeScopeVariableNames = $null
        $script:runnerScriptVariableNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@('Environment', 'CompositeOnly'))
        $baselineParameters = @{ Site = 'Parent' }
        $baselineVariables  = @{ Environment = 'Test' }
        $script:Environment = 'Test'
    }

    AfterEach {
        Remove-Variable -Name Environment, CompositeOnly -Scope Script -ErrorAction SilentlyContinue
    }

    It "Restores the file's baseline when the resource has no composite scope" {
        $parameters['Leftover'] = 'x'
        $variables['Leftover'] = 'x'

        Set-CompositeScope -CompositeScope @() -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        $parameters.Keys | Should -Be @('Site')
        $variables.Keys | Should -Be @('Environment')
    }

    It "Applies a layer's parameters and variables over the baseline" {
        $layer = @{ Composite = 'composite/A'; Parameters = @{ Site = 'Contoso' }; Variables = @{ Environment = 'Prod' } }

        Set-CompositeScope -CompositeScope @($layer) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        $parameters['Site'] | Should -Be 'Contoso'
        $variables['Environment'] | Should -Be 'Prod'
        $script:Environment | Should -Be 'Prod'
    }

    It "Resolves a later layer against the values set by an earlier one" {
        $outer = @{ Composite = 'composite/Outer'; Parameters = @{ Site = 'Contoso' }; Variables = @{} }
        $inner = @{ Composite = 'composite/Inner'; Parameters = @{ InnerSite = '<from:Site>' }; Variables = @{} }

        Set-CompositeScope -CompositeScope @($outer, $inner) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        $parameters['InnerSite'] | Should -Be 'Contoso'
    }

    It "Puts script variables back after leaving a composite" {
        $layer = @{ Composite = 'composite/A'; Parameters = @{}; Variables = @{ Environment = 'Prod'; CompositeOnly = 'yes' } }
        Set-CompositeScope -CompositeScope @($layer) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        Set-CompositeScope -CompositeScope @() -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        $script:Environment | Should -Be 'Test'
        Get-Variable -Name CompositeOnly -Scope Script -ErrorAction Ignore | Should -BeNullOrEmpty
        $variables.ContainsKey('CompositeOnly') | Should -BeFalse
    }

    It "Keeps two composites that declare the same name apart" {
        $a = @{ Composite = 'composite/A'; Parameters = @{ Site = 'A' }; Variables = @{} }
        $b = @{ Composite = 'composite/B'; Parameters = @{ Site = 'B' }; Variables = @{} }

        Set-CompositeScope -CompositeScope @($a) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables
        $parameters['Site'] | Should -Be 'A'

        Set-CompositeScope -CompositeScope @($b) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables
        $parameters['Site'] | Should -Be 'B'
    }

    It "Does not create a script variable for a reserved name" {
        Mock Write-Warning
        $layer = @{ Composite = 'composite/A'; Parameters = @{}; Variables = @{ VerbosePreference = 'Continue' } }
        $before = $VerbosePreference

        Set-CompositeScope -CompositeScope @($layer) -BaselineParameters $baselineParameters -BaselineVariables $baselineVariables

        $VerbosePreference | Should -Be $before
        $variables['VerbosePreference'] | Should -Be 'Continue'
        Should -Invoke Write-Warning -Times 1
    }
}
