
Describe "SetVariables Function Tests" -Tag Unit, LCM, Configuration {

    BeforeAll {
         # Load the functions to test
         $preParseFilePath = (Get-FunctionPath 'SetVariables.ps1').FullName

         . $preParseFilePath
    }

    BeforeEach {
        # Initialize empty target hashtable
        $global:target = @{}
    }

    It "should create script-level variables with underscores replacing dots" {
        $source = @{
            "Key.With.Dot" = "DotValue"
        }
        
        SetVariables -Source $source
        
        $script:Key_With_Dot | Should -Be "DotValue"
    }


    AfterEach {
        # Clean up environment variables and script variables
        Remove-Item -Path env:EnvVar -ErrorAction SilentlyContinue
        Remove-Variable -Name Key_With_Dot -Scope Script -ErrorAction SilentlyContinue
    }
}
