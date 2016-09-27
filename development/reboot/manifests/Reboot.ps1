Configuration Reboot
{
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    
    Script Reboot
    {
        TestScript = {
            return (Test-Path HKLM:\SOFTWARE\MyMainKey\RebootKey)
        }
        SetScript = {
            New-Item -Path HKLM:\SOFTWARE\MyMainKey\RebootKey -Force
                $global:DSCMachineStatus = 1 

        }
        GetScript = { return @{result = 'result'}}
    }

    Script Error
    {
        TestScript = {
            throw "This did not work"
            return $true
        }
        SetScript = { 

        }
        GetScript = { return @{result = 'result'}}
        DependsOn = "[Script]Reboot"
    }
}
