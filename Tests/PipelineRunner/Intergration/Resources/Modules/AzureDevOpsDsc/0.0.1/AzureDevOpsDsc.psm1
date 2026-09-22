enum Ensure
{
    Present
    Absent
}

class DscResourceBase
{

    [DscProperty()]
    [Ensure]
    $Ensure

    [DscProperty(NotConfigurable)]
    [Alias('result')]
    [HashTable]$LookupResult


    [System.Boolean]Test()
    {
        return $true
    }

    [void]Set()
    {
    }

}

[DscResource()]
class AzDoOrganizationGroup : DscResourceBase
{
    [DscProperty(Key, Mandatory)]
    [Alias('Name')]
    [System.String]$GroupName

    [DscProperty()]
    [Alias('Description')]
    [System.String]$GroupDescription

    AzDoOrganizationGroup()
    {
    }

    [AzDoOrganizationGroup] Get()
    {
        return [AzDoOrganizationGroup]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.GroupName           = $CurrentResourceObject.GroupName
        $properties.GroupDescription    = $CurrentResourceObject.GroupDescription
        $properties.Ensure              = $CurrentResourceObject.Ensure
        $properties.LookupResult        = $CurrentResourceObject.LookupResult
        #$properties.Reasons             = $CurrentResourceObject.LookupResult.Reasons

        Write-Verbose "[AzDoOrganizationGroup] Current state properties: $($properties | Out-String)"

        return $properties
    }
}

[DscResource()]
class AzDoProject : DscResourceBase
{
    [DscProperty(Key, Mandatory)]
    [Alias('Name')]
    [System.String]$ProjectName

    [DscProperty()]
    [Alias('Description')]
    [System.String]$ProjectDescription

    [DscProperty()]
    [ValidateSet('Git', 'Tfvc')]
    [System.String]$SourceControlType = 'Git'

    [DscProperty()]
    [ValidateSet('Agile', 'Scrum', 'CMMI', 'Basic')]
    [System.String]$ProcessTemplate = 'Agile'

    [DscProperty()]
    [ValidateSet('Public', 'Private')]
    [System.String]$Visibility = 'Private'

    AzDoProject()
    {
    }

    [AzDoProject] Get()
    {
        return [AzDoProject]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.ProjectName         = $CurrentResourceObject.ProjectName
        $properties.ProjectDescription  = $CurrentResourceObject.ProjectDescription
        $properties.SourceControlType   = $CurrentResourceObject.SourceControlType
        $properties.ProcessTemplate     = $CurrentResourceObject.ProcessTemplate
        $properties.Visibility          = $CurrentResourceObject.Visibility
        $properties.LookupResult        = $CurrentResourceObject.LookupResult
        $properties.Ensure              = $CurrentResourceObject.Ensure

        Write-Verbose "[AzDoGroupPermission] Current state properties: $($properties | Out-String)"

        return $properties

    }

}

[DscResource()]
class AzDoProjectServices : DscResourceBase
{
    [DscProperty(Mandatory, Key)]
    [Alias('Name')]
    [System.String]$ProjectName

    [DscProperty()]
    [Alias('Repos')]
    [ValidateSet('Enabled', 'Disabled')]
    [System.String]$GitRepositories = 'Enabled'

    [DscProperty()]
    [Alias('Board')]
    [ValidateSet('Enabled', 'Disabled')]
    [System.String]$WorkBoards = 'Enabled'

    [DscProperty()]
    [Alias('Pipelines')]
    [ValidateSet('Enabled', 'Disabled')]
    [System.String]$BuildPipelines = 'Enabled'

    [DscProperty()]
    [Alias('Tests')]
    [ValidateSet('Enabled', 'Disabled')]
    [System.String]$TestPlans = 'Enabled'

    [DscProperty()]
    [Alias('Artifacts')]
    [ValidateSet('Enabled', 'Disabled')]
    [System.String]$AzureArtifact = 'Enabled'

    AzDoProjectServices()
    {
    }

    [AzDoProjectServices] Get()
    {
        return [AzDoProjectServices]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.ProjectName         = $CurrentResourceObject.ProjectName
        $properties.GitRepositories     = $CurrentResourceObject.GitRepositories
        $properties.WorkBoards          = $CurrentResourceObject.WorkBoards
        $properties.BuildPipelines      = $CurrentResourceObject.BuildPipelines
        $properties.TestPlans           = $CurrentResourceObject.TestPlans
        $properties.AzureArtifact       = $CurrentResourceObject.AzureArtifact
        $properties.Ensure              = $CurrentResourceObject.Ensure
        $properties.LookupResult        = $CurrentResourceObject.LookupResult

        Write-Verbose "[AzDoProjectGroup] Current state properties: $($properties | Out-String)"

        return $properties
    }

}

[DscResource()]
class AzDoProjectGroup : DscResourceBase
{
    [DscProperty(Key, Mandatory)]
    [Alias('Name')]
    [System.String]$GroupName

    [DscProperty(Mandatory)]
    [Alias('Project')]
    [System.String]$ProjectName

    [DscProperty()]
    [Alias('Description')]
    [System.String]$GroupDescription

    AzDoProjectGroup()
    {
    }

    [AzDoProjectGroup] Get()
    {
        return [AzDoProjectGroup]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.GroupName           = $CurrentResourceObject.GroupName
        $properties.GroupDescription    = $CurrentResourceObject.GroupDescription
        $properties.ProjectName         = $CurrentResourceObject.ProjectName
        $properties.Ensure              = $CurrentResourceObject.Ensure
        $properties.LookupResult        = $CurrentResourceObject.LookupResult
        #$properties.Reasons             = $CurrentResourceObject.LookupResult.Reasons

        Write-Verbose "[AzDoProjectGroup] Current state properties: $($properties | Out-String)"

        return $properties
    }

}

[DscResource()]
class AzDoGroupMember : DscResourceBase
{
    [DscProperty(Key, Mandatory)]
    [Alias('Name')]
    [System.String]$GroupName

    [DscProperty(Mandatory)]
    [Alias('Members')]
    [System.String[]]$GroupMembers

    AzDoGroupMember()
    {
    }

    [AzDoGroupMember] Get()
    {
        return [AzDoGroupMember]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.GroupName           = $CurrentResourceObject.GroupName
        $properties.GroupMembers        = $CurrentResourceObject.GroupMembers
        $properties.Ensure              = $CurrentResourceObject.Ensure
        $properties.LookupResult        = $CurrentResourceObject.LookupResult

        Write-Verbose "[AzDoProjectGroup] Current state properties: $($properties | Out-String)"

        return $properties
    }

}

[DscResource()]
class AzDoGitRepository : DscResourceBase
{
    [DscProperty(Mandatory)]
    [Alias('Name')]
    [System.String]$ProjectName

    [DscProperty(Key, Mandatory)]
    [Alias('Repository')]
    [System.String]$RepositoryName

    [DscProperty()]
    [Alias('Source')]
    [System.String]$SourceRepository

    AzDoGitRepository()
    {
        $this.Construct()
    }

    [AzDoGitRepository] Get()
    {
        return [AzDoGitRepository]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.ProjectName         = $CurrentResourceObject.ProjectName
        $properties.RepositoryName      = $CurrentResourceObject.RepositoryName
        $properties.SourceRepository    = $CurrentResourceObject.SourceRepository
        $properties.Ensure              = $CurrentResourceObject.Ensure
        $properties.LookupResult        = $CurrentResourceObject.LookupResult

        Write-Verbose "[AzDoProjectGroup] Current state properties: $($properties | Out-String)"

        return $properties
    }

}

[DscResource()]
class AzDoGitPermission : DscResourceBase
{
    [DscProperty(Key, Mandatory)]
    [Alias('Name')]
    [System.String]$ProjectName

    [DscProperty(Mandatory)]
    [Alias('Repository')]
    [System.String]$RepositoryName

    [DscProperty()]
    [Alias('Inherited')]
    [System.Boolean]$isInherited=$true

    [DscProperty()]
    [HashTable[]]$Permissions

    AzDoGitPermission()
    {
    }

    [AzDoGitPermission] Get()
    {
        return [AzDoGitPermission]$($this.GetDscCurrentStateProperties())
    }

    hidden [Hashtable]GetDscCurrentStateProperties([PSCustomObject]$CurrentResourceObject)
    {
        $properties = @{
            Ensure = [Ensure]::Absent
        }

        # If the resource object is null, return the properties
        if ($null -eq $CurrentResourceObject)
        {
            return $properties
        }

        $properties.ProjectName           = $CurrentResourceObject.ProjectName
        $properties.RepositoryName        = $CurrentResourceObject.RepositoryName
        $properties.isInherited           = $CurrentResourceObject.isInherited
        $properties.Permissions           = $CurrentResourceObject.Permissions
        $properties.lookupResult          = $CurrentResourceObject.lookupResult
        $properties.Ensure                = $CurrentResourceObject.Ensure

        Write-Verbose "[AzDoGitPermission] Current state properties: $($properties | Out-String)"

        return $properties
    }

}