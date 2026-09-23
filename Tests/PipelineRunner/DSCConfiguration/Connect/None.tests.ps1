Describe "Actions/Connect/None Action Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $script:actionPath = (Get-FunctionPath 'None.ps1').FullName

    }

    It "should return null when no context is supplied" {
        $result = & $script:actionPath
        $result | Should -BeNullOrEmpty
    }

    It "should return null regardless of what the context contains" {
        $result = & $script:actionPath -Context @{ Whatever = 'value'; Another = 123 }
        $result | Should -BeNullOrEmpty
    }

    It "should not throw" {
        { & $script:actionPath -Context @{} } | Should -Not -Throw
    }

}
