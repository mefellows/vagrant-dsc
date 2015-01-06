configuration WebServer 
{
    #Install the IIS Role
    File website
    {
      Ensure = "Present"
      Type = "Directory"
      DestinationPath = "c:\mywebroot\bin"
    }
}