Configuration MyWebsite
{
  param ($MachineName)

  Node $MachineName
  {
    #Install the IIS Role
    File website
    {
      Ensure = "Present"
      Type = "Directory"
      DestinationPath = "c:\mywebroot"
    }
  }
}

Write-Output "Hello from DSC Provisioner: Config file"