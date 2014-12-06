Configuration SimpleWebsite
{
    param
    (
        [String]$WebAppPath = "c:\myWebApp",
        [String]$WebAppName = "MyWebApp",
        [HashTable]$AuthenticationInfo = @{Anonymous = "true"; Basic = "false"; Digest = "false"; Windows = "false"}
    )

    Import-DscResource -Module cWebAdministration

    # Create the new Website    
    cWebsite Basic
    {
        Ensure          = 'Present'
        Name            = $WebAppName
        PhysicalPath    = $WebAppPath
        ApplicationPool = "DefaultAppPool"
        AuthenticationInfo = SEEK_cWebAuthenticationInformation
        {
            Anonymous = $AuthenticationInfo.Anonymous
            Basic = $AuthenticationInfo.Basic
            Digest = $AuthenticationInfo.Digest
            Windows = $AuthenticationInfo.Windows
        }
        DependsOn  = '[File]website'
    }

    File websiteIndex
    {
      Ensure = "Present"
      Type = "File"
      DestinationPath = "$WebAppPath\index.html"
      SourcePath = "c:\vagrant\website\index.html"
      DependsOn  = '[File]website'
    }

    File website
    {
      Ensure = "Present"
      Type = "Directory"
      DestinationPath = $WebAppPath
    }
}