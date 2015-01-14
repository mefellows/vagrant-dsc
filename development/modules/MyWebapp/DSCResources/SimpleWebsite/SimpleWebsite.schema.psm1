Configuration SimpleWebsite
{
    param
    (
        [String]$WebAppPath = "c:\myWebApp",
        [String]$WebAppName = "MyWebApp",
        [HashTable]$AuthenticationInfo = @{Anonymous = "true"; Basic = "false"; Digest = "false"; Windows = "false"}
    )

    # Import-DscResource -Module cWebAdministration
    Import-DscResource -Module xWebAdministration 

     # Stop the default website 
    xWebsite DefaultSite  
    { 
        Ensure          = "Present" 
        Name            = "Default Web Site" 
        State           = "Stopped" 
        PhysicalPath    = "C:\inetpub\wwwroot" 
        DependsOn       = "[File]websiteIndex" 
    }

    # Create a Web Application Pool 
    xWebAppPool NewWebAppPool 
    { 
        Name   = "${WebAppName}AppPool"
        Ensure = "Present" 
        State  = "Started" 
    } 

    #Create a New Website with Port 
    xWebSite NewWebSite 
    { 
        Name   = $WebAppName
        Ensure = "Present" 
        BindingInfo = MSFT_xWebBindingInformation 
                    { 
                        Port = 80
                    } 
        PhysicalPath = $WebAppPath
        State = "Started" 
        DependsOn = @("[xWebAppPool]NewWebAppPool") 
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