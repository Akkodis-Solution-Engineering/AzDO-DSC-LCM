
Describe "ConvertTo-DscV3ConfigurationDocument Function Tests" -Tag Unit {

    BeforeAll {

        # Load the function to test and its dependency
        $testDscV3ResourceTypePath = (Get-FunctionPath 'Test-DscV3ResourceType.ps1').FullName
        $functionFilePath = (Get-FunctionPath 'ConvertTo-DscV3ConfigurationDocument.ps1').FullName

        . $testDscV3ResourceTypePath
        . $functionFilePath

    }

    Context "Schema and shape" {

        It "Stamps the document with the default DSC v3 schema URI" {
            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @()

            $doc['$schema'] | Should -Be 'https://aka.ms/dsc/schemas/v3/bundled/config/document.json'
        }

        It "Stamps the document with a custom schema URI when supplied" {
            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @() -SchemaUri 'https://example.com/custom-schema.json'

            $doc['$schema'] | Should -Be 'https://example.com/custom-schema.json'
        }

        It "Returns an empty resources array when no resources are supplied" {
            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @()

            @($doc.resources).Count | Should -Be 0
        }

        It "Keeps only name, type and properties, dropping pipeline-only keys" {
            $resource = @{
                name                = 'MyResource'
                type                = 'Microsoft.Windows/Registry'
                properties          = @{ Key = 'Value' }
                condition           = 'someCondition'
                postExecutionScript = 'Write-Host done'
                dependsOn           = @('Microsoft.Windows/Registry/Other')
                parameters          = @{ p = 1 }
                conditions          = @{ c = 1 }
                variables           = @{ v = 1 }
            }

            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @($resource)

            @($doc.resources).Count | Should -Be 1
            $emitted = $doc.resources[0]
            $emitted.Keys | Sort-Object | Should -Be @('name', 'properties', 'type')
            $emitted.name | Should -Be 'MyResource'
            $emitted.type | Should -Be 'Microsoft.Windows/Registry'
            $emitted.properties['Key'] | Should -Be 'Value'
        }

        It "Preserves resource order" {
            $resources = @(
                @{ name = 'First';  type = 'Microsoft/OSInfo'; properties = @{} }
                @{ name = 'Second'; type = 'Microsoft/OSInfo'; properties = @{} }
            )

            $doc = ConvertTo-DscV3ConfigurationDocument -Resource $resources

            $doc.resources[0].name | Should -Be 'First'
            $doc.resources[1].name | Should -Be 'Second'
        }

        It "Defaults properties to an empty hashtable when absent" {
            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @(@{ name = 'NoProps'; type = 'Microsoft/OSInfo' })

            ($null -eq $doc.resources[0].properties) | Should -BeFalse -Because 'properties should default to an (empty) object, not $null'
            $doc.resources[0].properties | Should -BeOfType ([hashtable])
            @($doc.resources[0].properties.Keys).Count | Should -Be 0
        }

        It "Accepts a [pscustomobject] resource as well as a [hashtable]" {
            $resource = [pscustomobject]@{ name = 'PSObjResource'; type = 'Microsoft/OSInfo'; properties = @{ Key = 'Value' } }

            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @($resource)

            $doc.resources[0].name | Should -Be 'PSObjResource'
            $doc.resources[0].properties['Key'] | Should -Be 'Value'
        }

        It "Reads keys case-insensitively" {
            $resource = @{ NAME = 'CasedResource'; Type = 'Microsoft/OSInfo'; PROPERTIES = @{ Key = 'Value' } }

            $doc = ConvertTo-DscV3ConfigurationDocument -Resource @($resource)

            $doc.resources[0].name | Should -Be 'CasedResource'
        }

    }

    Context "Compliance validation" {

        It "Throws when a resource has no name" {
            $resource = @{ type = 'Microsoft/OSInfo'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) } | Should -Throw "*missing a non-empty 'name'*"
        }

        It "Throws when a resource has no type" {
            $resource = @{ name = 'MyResource'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) } | Should -Throw "*missing a non-empty 'type'*"
        }

        It "Throws when a resource's type is not a DSC v3 identifier" {
            $resource = @{ name = 'MyResource'; type = 'NotNamespacedType'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) } | Should -Throw "*not a DSC v3 resource identifier*"
        }

        It "Aggregates every problem into a single thrown error" {
            $resources = @(
                @{ type = 'Microsoft/OSInfo'; properties = @{} }
                @{ name = 'MyResource'; properties = @{} }
            )

            { ConvertTo-DscV3ConfigurationDocument -Resource $resources } | Should -Throw "*2 resource(s) are not DSC v3 compliant*"
        }

    }

    Context "Resource availability validation" {

        It "Does not throw when AvailableResourceType is not supplied" {
            $resource = @{ name = 'MyResource'; type = 'Microsoft.Vendor/Widget'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) } | Should -Not -Throw
        }

        It "Does not throw when the resource's type is present in AvailableResourceType" {
            $resource = @{ name = 'MyResource'; type = 'Microsoft/OSInfo'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) -AvailableResourceType @('Microsoft/OSInfo') } | Should -Not -Throw
        }

        It "Throws when the resource's type is not present in AvailableResourceType" {
            $resource = @{ name = 'MyResource'; type = 'Microsoft/OSInfo'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) -AvailableResourceType @('Microsoft.Windows/Registry') } | Should -Throw "*not available to dsc.exe*"
        }

        It "Does not apply the availability check when AvailableResourceType is empty" {
            $resource = @{ name = 'MyResource'; type = 'Microsoft/OSInfo'; properties = @{} }

            { ConvertTo-DscV3ConfigurationDocument -Resource @($resource) -AvailableResourceType @() } | Should -Not -Throw
        }

    }

}
