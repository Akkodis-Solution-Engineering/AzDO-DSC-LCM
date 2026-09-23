Describe "Test-DscV3ResourceType Function Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        $functionPath = (Get-FunctionPath 'Test-DscV3ResourceType.ps1').FullName
        . $functionPath

    }

    Context "When the Type string is null, empty, or whitespace" {

        It "should return false for null" {
            Test-DscV3ResourceType -Type $null | Should -BeFalse
        }

        It "should return false for an empty string" {
            Test-DscV3ResourceType -Type '' | Should -BeFalse
        }

        It "should return false for whitespace" {
            Test-DscV3ResourceType -Type '   ' | Should -BeFalse
        }

    }

    Context "When the Type string is a structurally valid DSC v3 resource type" {

        It "should return true for a simple namespace/name pair" {
            Test-DscV3ResourceType -Type 'Microsoft/OSInfo' | Should -BeTrue
        }

        It "should return true for a dotted namespace" {
            Test-DscV3ResourceType -Type 'Microsoft.Windows/Registry' | Should -BeTrue
        }

        It "should return true for a multi-segment dotted namespace" {
            Test-DscV3ResourceType -Type 'Microsoft.DSC.Debug/Echo' | Should -BeTrue
        }

        It "should return true for a DSC v2 module/resource pair (structurally identical)" {
            Test-DscV3ResourceType -Type 'PSDscResources/Service' | Should -BeTrue
        }

    }

    Context "When the Type string is structurally invalid" {

        It "should return false for a bare name with no slash" {
            Test-DscV3ResourceType -Type 'JustAName' | Should -BeFalse
        }

        It "should return false when there is more than one slash" {
            Test-DscV3ResourceType -Type 'Microsoft/Windows/Registry' | Should -BeFalse
        }

        It "should return false for an empty namespace segment" {
            Test-DscV3ResourceType -Type '/Registry' | Should -BeFalse
        }

        It "should return false for an empty name segment" {
            Test-DscV3ResourceType -Type 'Microsoft/' | Should -BeFalse
        }

        It "should return false when the string contains embedded whitespace" {
            Test-DscV3ResourceType -Type 'Micro soft/Registry' | Should -BeFalse
        }

        It "should return false when a dotted segment starts with a digit" {
            Test-DscV3ResourceType -Type '1Microsoft/Registry' | Should -BeFalse
        }

        It "should return false when a dot-separated segment is empty (double dot)" {
            Test-DscV3ResourceType -Type 'Microsoft..Windows/Registry' | Should -BeFalse
        }

    }

}
