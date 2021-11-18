# Add variables
$repo = "http://192.168.1.200"
$esxiOva = "Nested_ESXi7.0u3_Appliance_Template_v1.ova"
$installEsxi = $true
$installVcsa = $false
$vcsaDirectory = "/nested/vcsa/"

# From WL
$NestedESXiHostnameToIPs = @{
    "tanzu-esxi-1" = "192.168.1.211"
    "tanzu-esxi-2" = "192.168.1.212"
    "tanzu-esxi-3" = "192.168.1.213"
}

# Nested ESXi VM Resources
$NestedESXivCPU = "4"
$NestedESXivMEM = "24" #GB
$NestedESXiCachingvDisk = "8" #GB
$NestedESXiCapacityvDisk = "100" #GB

# VCSA Deployment Configuration
$VCSADeploymentSize = "tiny"
$VCSADisplayName = "tanzu-vcsa-3"
$VCSAIPAddress = "192.168.1.210"
$VCSAHostname = "192.168.1.210" #Change to IP if you don't have valid DNS
$VCSAPrefix = "24"
$VCSASSODomainName = "vsphere.local"
$VCSASSOPassword = "VMware1!"
$VCSARootPassword = "VMware1!"
$VCSASSHEnable = "true"

# General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
$VMDatacenter = "DC"
$VMCluster = "Cl1"
$VMNetwork = "VM Network"
$VMDatastore = "datastore1"
$VMNetmask = "255.255.255.0"
$VMGateway = "192.168.1.1"
$VMDNS = "192.168.1.200"
$VMNTP = "pool.ntp.org"
$VMPassword = "VMware1!"
$VMDomain = "corp.local"
$VMSyslog = "192.168.1.200"
$VMFolder = "Nested"
# Applicable to Nested ESXi only
$VMSSH = "true"
$VMVMFS = "false"

# Name of new vSphere Datacenter/Cluster when VCSA is deployed
$NewVCDatacenterName = "Tanzu-Datacenter"
$NewVCVSANClusterName = "Workload-Cluster"
$NewVCVDSName = "Tanzu-VDS"
$NewVCDVPGName = "DVPG-Management Network"

## Do not edit below here
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$VAppName = "Nested-vSphere-with-Tanzu-NSX-T-Lab-$random_string"

$preCheck = 1
$confirmDeployment = 1
$deployNestedESXiVMs = 1
$deployVCSA = 1
$setupNewVC = 1
$addESXiHostsToVC = 1
$configureVSANDiskGroup = 1
$configureVDS = 1
$clearVSANHealthCheckAlarm = 1
$setupTanzuStoragePolicy = 1
$setupTKGContentLibrary = 1
$deployNSXManager = 1
$deployNSXEdge = 1
$postDeployNSXConfig = 1
$setupTanzu = 1
$moveVMsIntovApp = 1

$esxiTotalCPU = 0
$vcsaTotalCPU = 0
$nsxManagerTotalCPU = 0
$nsxEdgeTotalCPU = 0
$esxiTotalMemory = 0
$vcsaTotalMemory = 0
$nsxManagerTotalMemory = 0
$nsxEdgeTotalMemory = 0
$esxiTotalStorage = 0
$vcsaTotalStorage = 0
$nsxManagerTotalStorage = 0
$nsxEdgeTotalStorage = 0

$StartTime = Get-Date



$ovaPath = "/working/repo/esxi/" + $esxiOva
if ($installEsxi -eq $true) {
    # download from the repo 
    # keeps running out of memory
    # $getEsxi = Invoke-WebRequest -Uri "$repo/repo/esxi/$esxiOva" -OutFile $ovfPath
    $repoPath = $repo + "/repo/esxi/"
    Write-Host "Repo path is " $repoPath
    # works 
    # wget -mxnp -nv  -nH http://192.168.1.200/repo/esxi/ -P /working -R "index.html*"
    wget -mxnp -nv -nH $repoPath -P "/working" -R "index.html*" 
    # if (-not $getEsxi) {
    #     throw "Error downloading ESXi OVA."
    # }
}
else {
    Write-Host "ESXi will not be installed"
}

if ($installVcsa -eq $true) {
    if (-not(Test-Path -Path $vcsaDirectory)) {
        Write-Host "VCSA folder will be downloaded."
        $repoPath = $repo + "/repo/vcsa/"
        wget -mxnp -nH $repoPath  -P "/working/" -R "index.html*" -l7
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

# Write-Host "OVA configuration"
# Write-Host $ovaConfiguration.ToHashTable().Keys

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

# print out the OVA settings
$ovfconfig = $ovaConfiguration.TohashTable()
$ovfconfig.GetEnumerator() | ForEach-Object {
    $message = 'key {0} value {1}' -f $_.key, $_.value
    Write-Host $message
}


Write-Host $ovaConfiguration | Format-Custom -Depth 3
$vm = Import-VApp -Name 'testesxi.corp.local' -Source $ovaPath -VMHost $target -Datastore $datastore -OvfConfiguration $ovaConfiguration
if ( -not $vm ) {
    throw "Nested ESXi host did not get deployed."
}


# Deploy OVA into vCenter

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
