# Sets up DSC
echo 'Setting up DSC components'

$ChocoInstallPathOld = "$env:SystemDrive\Chocolatey\bin"
$ChocoInstallPath = "$env:SystemDrive\ProgramData\Chocolatey\bin"

# Install chocolatey
if ( !(Get-Command "choco") -and !(Test-Path $ChocoInstallPath)) {
  iex ((new-object net.webclient).DownloadString('http://chocolatey.org/install.ps1'))
}

choco install DotNet4.5
choco install powershell4