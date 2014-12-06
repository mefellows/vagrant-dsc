Configuration MyWebsite
{
  param ($MachineName)

  Import-DscResource -Module cWebAdministration
  Import-DscResource -Module MyWebapp

  Node $MachineName
  {
    WindowsFeature IIS
    {
        Ensure = "Present"
        Name = "Web-Server"
    }
    cWebsite DefaultWebsite
    {
        Name = "Default Web Site"
        ApplicationPool = "DefaultAppPool"
        PhysicalPath = "$env:SystemDrive\inetpub\wwwroot"
        Ensure = "Absent"
        DependsOn  = '[WindowsFeature]IIS'
    }
        
    SimpleWebsite sWebsite
    {
        WebAppPath = "c:\my-new-webapp"
        DependsOn  = '[cWebsite]DefaultWebsite'
    }    
  }
}