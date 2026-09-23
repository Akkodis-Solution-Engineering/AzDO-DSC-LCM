Describe "Local Function Tests" -Tag Unit, PipelineRunner, Target {

    BeforeAll {
        # 'Local.ps1' also exists under Actions/Source (a different hook); disambiguate by
        # directory since Get-FunctionPath matches by filename across the whole repo.
        $script:LocalPath = (Get-FunctionPath 'Local.ps1' | Where-Object { $_.Directory.Name -eq 'Target' }).FullName
    }

    It "Returns a non-remote session descriptor with no CimSession/PSSession" {
        $result = & $script:LocalPath -Context @{}

        $result.IsRemote | Should -BeFalse
        $result.CimSession | Should -BeNullOrEmpty
        $result.PSSession | Should -BeNullOrEmpty
        $result.ComputerName | Should -Be 'localhost'
    }

    It "Ignores whatever context is supplied (present only for signature consistency)" {
        $result = & $script:LocalPath -Context @{ ComputerName = 'ignored'; Credential = 'ignored' }

        $result.ComputerName | Should -Be 'localhost'
        $result.IsRemote | Should -BeFalse
    }
}
