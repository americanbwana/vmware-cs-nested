# import from variable file 
# Generated and saved in CS stage.
. "/working/variables.ps1"
# make sure they were imported
if (-not $vCenter) {
    throw "variable.ps1 not imported"
} else {
    Write-Host "Variables were imported, for example $vCenter"
}
# Add variables
$repo = "http://192.168.1.200"
$esxiOva = "Nested_ESXi7.0u3_Appliance_Template_v1.ova"
$installEsxi = $true
$installVcsa = $false
$vcsaDirectory = "/nested/vcsa/"
$VIServer = $vCenter
$VIUsername = $vCenterUser
$VIPassword = $vCenterPass

# From WL
$NestedESXiHostnameToIPs = @{
    $Esxi01Name = $Esxi01Ip
    $Esxi02Name = $Esxi02Ip
    $Esxi03Name = $Esxi03Ip
}

Write-Host "hostnameToIp map" $NestedESXiHostnameToIPs

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
$VMCluster = "CL1"
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
$VMSSH = $true
$VMVMFS = $false

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

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# if( $deployNestedESXiVMs -eq 1 -or $deployVCSA -eq 1 -or $deployNSXManager -eq 1 -or $deployNSXEdge -eq 1) {
if( $installEsxi -eq $true -or $installVcsa -eq $true) {

    
    Write-Host "Connecting to Management vCenter Server $VIServer ..."
    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
    $cluster = Get-Cluster -Server $viConnection -Name $VMCluster
    $datacenter = $cluster | Get-Datacenter
    $vmhost = $cluster | Get-VMHost | Select -First 1
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


# Deploy OVA into vCenter

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
