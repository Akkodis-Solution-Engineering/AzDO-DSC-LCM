
Describe "stopProcessing Function Tests" -Tag Unit, PipelineRunner, Runner {

    BeforeAll {
        . (Get-FunctionPath 'stopProcessing.ps1').FullName
    }

    BeforeEach {
        $script:StopTaskProcessing = $false
    }

    It "sets the module-scope StopTaskProcessing flag" {
        stopProcessing

        $script:StopTaskProcessing | Should -BeTrue
    }

    It "returns a truthy value" {
        $result = stopProcessing
        $result | Should -BeTrue
    }

    It "is callable via its 'stopProcessing' alias and still sets the flag" {
        $null = stopProcessing
        $script:StopTaskProcessing | Should -BeTrue
    }
}
