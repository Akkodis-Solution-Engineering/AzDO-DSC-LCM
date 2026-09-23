Describe "Static Function Tests" -Tag Unit, PipelineRunner, Credential {

    BeforeAll {
        $script:StaticPath = (Get-FunctionPath 'Static.ps1').FullName
        Mock -CommandName Write-Warning
    }

    It "Throws when UserName or Password is missing" {
        { & $script:StaticPath -Context @{} } | Should -Throw "*required*"
        { & $script:StaticPath -Context @{ UserName = 'x' } } | Should -Throw "*required*"
    }

    It "Throws when UserName is blank even when Password is supplied" {
        { & $script:StaticPath -Context @{ UserName = ''; Password = 'super-secret' } } | Should -Throw "*required*"
    }

    It "Builds a PSCredential from a plain-text password and warns about its use" {
        $result = & $script:StaticPath -Context @{ UserName = 'svc-account'; Password = 'super-secret' }

        $result | Should -BeOfType ([System.Management.Automation.PSCredential])
        $result.UserName | Should -Be 'svc-account'
        $result.GetNetworkCredential().Password | Should -Be 'super-secret'
        Assert-MockCalled -CommandName Write-Warning -Exactly 1 -Scope It
    }

    It "Accepts an already-secure password without re-wrapping it" {
        $secure = ConvertTo-SecureString -String 'super-secret' -AsPlainText -Force

        $result = & $script:StaticPath -Context @{ UserName = 'svc-account'; Password = $secure }

        $result.GetNetworkCredential().Password | Should -Be 'super-secret'
    }

    It "Warns on every use, including with an already-secure password" {
        $secure = ConvertTo-SecureString -String 'super-secret' -AsPlainText -Force

        $null = & $script:StaticPath -Context @{ UserName = 'svc-account'; Password = $secure }

        Assert-MockCalled -CommandName Write-Warning -Exactly 1 -Scope It
    }
}
