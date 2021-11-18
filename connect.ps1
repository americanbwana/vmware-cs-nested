# Add variables
$repo = "http://192.168.1.200"
$esxiOva = "Nested_ESXi7.0u3_Appliance_Template_v1.ova"
$volume = "/nested"
$installEsxi = $true
$installVcsa = $false
$vcsaDirectory = "/nested/vcsa/"
# Make sure volume is mounted and required files are available
# the volume should be mounted on /nested
# 
# if (-not(Test-Path $volume)) {
#     throw "Docker volume $volume is not mounted."
# }
$ovaPath = "/working/repo/esxi/" + $esxiOva
if ($installEsxi -eq $true) {
    # download from the repo 
    # keeps running out of memory
    # $getEsxi = Invoke-WebRequest -Uri "$repo/repo/esxi/$esxiOva" -OutFile $ovfPath
    $repoPath = $repo + "/repo/esxi/" + $esxiOva
    Write-Host "Repo path is " + $repoPath
    wget -mxnpq -nH $ -P "/working/" -R "index.html*" 
    if (-not $getEsxi) {
        throw "Error downloading ESXi OVA."
    }
}
else {
    Write-Host "ESXi will not be installed"
}

if ($installVcsa -eq $true) {
    if (-not(Test-Path -Path $vcsaDirectory)) {
        Write-Host "VCSA folder will be downloaded onto $volume"
        wget -mxnpq -nH http://192.168.1.200/repo/vcsa/  -P "/working/" -R "index.html*" -l7
        # need to set X on ovftool* and vsca-deploy*
        # takes about 7 minutes to download vcsa repo. 8.1G

    }
}

du repo/

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# print out ENV
# $myEnv = Get-ChildItem Env:\
# write-host $myEnv
# connect using Env. 
$vcenter = Connect-VIserver -User $Env:vCenterUser -Password $Env:vCenterPass -Server $Env:vCenter 
Write-Host "Connected to " $vcenter.Name


# Verify the connection by listing the datacenters
$datacenter = Get-Datacenter

# get the datastore
$datastore = Get-Datastore -Name 'datastore1'

Write-Host $datacenter.Name
$target = Get-VMHost -Name 'esx01.corp.local' 
Write-Host $target.Name

# # find the content library
# $contentLibrary = Get-ContentLibrary -Name $env:contentLibary
# Write-Host "Found content library " $contentLibrary.Name
# # get the contentLibraryItem config
# $contentLibaryItem = Get-ContentLibraryItem -Name $env:contentLibraryItem -ContentLibrary $contentLibary 
# Write-Host "Item name " $contentLibaryItem.Name

# Get OVA configuration
$ovaConfiguration = Get-OvfConfiguration -Ovf $ovaPath
if ( -not $ovaConfiguration ) {
    throw "Could not get ovaConfiguration.  Maybe the path is wrong, or it didn't get downloaded."
}

Write-Host "OVA configuration"
Write-Host $ovaConfiguration.ToHashTable().Keys

# Change config
$ovaConfiguration.common.guestinfo.dns.value='192.168.1.200'
$ovaConfiguration.common.guestinfo.gateway.Value="192.168.1.1"
$ovaConfiguration.common.guestinfo.ntp.value="0.north-america.pool.ntp.org"
$ovaConfiguration.common.guestinfo.hostname.value="testesxi.corp.local"
$ovaConfiguration.common.guestinfo.netmask.value="255.255.255.0"
$ovaConfiguration.common.guestinfo.domain.value="corp.local"
$ovaConfiguration.common.guestinfo.ipaddress.value="192.168.1.210"
$ovaConfiguration.common.guestinfo.password.value="VMware1!"
$ovaConfiguration.common.guestinfo.ssh.value= $true
# $ovaConfiguration.EULAs.Accept.Value= $true
# $networkMapLabel = ($ovaConfiguration.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
# Write-Host $networkMapLabel
# $ovaConfiguraton.NetworkMapping.$networkMapLabel.value = 'VM Network'
# $ovaConfiguration.NetworkMapping.VM_Network="VM Network"
# $ovaConfiguration.Name="testesxi.corp.local"

Write-Host $ovaConfiguration | Format-Custom -Depth 3
$vm = Import-VApp -Name 'testesxi.corp.local' -Source $ovaPath -VMHost $target -Datastore $datastore -OvfConfiguration $ovaConfiguration
if ( -not $vm ) {
    throw "Nested ESXi host did not get deployed."
}
# Deploy OVA into vCenter

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
