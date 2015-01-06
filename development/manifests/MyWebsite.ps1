Configuration MyWebsite
{
  param ($MachineName)

  Import-DscResource -Module CommonConfigModule

  Node $MachineName
  {
    #Install the IIS Role
    File website
    {
      Ensure = "Present"
      Type = "Directory"
      DestinationPath = "c:\mywebroot"
    }

    #Test composite resource
    WebServer WebServer 
    {
        
    }
  }
}

Write-Output "Hello from DSC Provisioner: Config file"