Configuration SimpleWebsite
{
    param
    (
        [String]$WebAppPath             = "c:\myWebApp",
        [String]$WebSiteName            = "MyWebApp",
        [String]$HostNameSuffix         = "local",
        [String]$HostName               = "vagrantdsc.${HostNameSuffix}",
        [String]$ApiAppPoolName         = "MyWebAppPool",
        [HashTable]$AuthenticationInfo = @{Anonymous = "true"; Basic = "false"; Digest = "false"; Windows = "false"}
    )

    Import-DscResource -Module cWebAdministration
    Import-DscResource -Module cNetworking

    # Stop the default website
    cWebsite DefaultSite
    {
        Ensure          = "Absent"
        Name            = "Default Web Site"
        State           = "Stopped"
        PhysicalPath    = "C:\inetpub\wwwroot"
    }

    cWebsite UrlSvcWebsite
    {
        Ensure = "Present"
        Name   = $WebSiteName
        BindingInfo = @(SEEK_cWebBindingInformation
        {
            Protocol = "http"
            Port = 80
            IPAddress = "*"
        })
        AuthenticationInfo = SEEK_cWebAuthenticationInformation { Anonymous = "true" }
        HostFileInfo = @(SEEK_cHostEntryFileInformation
        {
            RequireHostFileEntry = $True
            HostEntryName = $HostName
            HostIpAddress = "10.0.0.30"
        })
        PhysicalPath = $WebAppPath
        State = "Started"
        DependsOn = @("[cWebsite]DefaultSite")
    }
}
