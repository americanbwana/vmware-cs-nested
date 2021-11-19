# import from variable file 
# Generated and saved in CS stage.
. /working/variables.ps1
# make sure they were imported
if (-not $vCenter) {
    throw "variable.ps1 not imported"
}
# Add variables
$repo = "http://192.168.1.200"
$esxiOva = "Nested_ESXi7.0u3_Appliance_Template_v1.ova"
$installEsxi = $true
$installVcsa = $false
$vcsaDirectory = "/nested/vcsa/"
$VIServer = $Env:vCenter
$VIUsername = $Env:vCenterUser
$VIPassword = $Env:vCenterPass

# From WL
$NestedESXiHostnameToIPs = @{
    $Env:Esxi01Name = $Env:Esxi01Ip
    $Env:Esxi02Name = $Env:Esxi02Ip
    $Env:Esxi03Name = $Env:Esxi03Ip
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

# Now loop through $NestedESXiHostnameToIP
if ($installEsxi -eq $true) {

    # Get OVA configuration
    $ovaConfiguration = Get-OvfConfiguration $ovaPath
    if ( -not $ovaConfiguration ) {
        throw "Could not get ovaConfiguration.  Maybe the path is wrong, or it didn't get downloaded."
    }
    # get the type
    Write-Host "config getType " $ovfConfiguration.getType()
    # Change config
    $ovaConfiguration.common.guestinfo.dns.value = $VMDNS
    $ovaConfiguration.common.guestinfo.gateway.Value = $VMGateway
    $ovaConfiguration.common.guestinfo.ntp.value = $VMNTP
    $ovaConfiguration.common.guestinfo.netmask.value = $VMNetmask
    $ovaConfiguration.common.guestinfo.domain.value = $VMDomain
    $ovaConfiguration.common.guestinfo.password.value = $VMPassword
    $ovaConfiguration.common.guestinfo.ssh.value = $true
    $ovaConfiguration.common.guestinfo.createvmfs.value = $false
    # $networkMapLabel = ($ovaConfiguration.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
    # Write-Host $networkMapLabel
    # $ovaConfiguraton.NetworkMapping.$networkMapLabel.value = $VMNetwork
    # $ovaConfiguration.NetworkMapping.VM_Network="VM Network"
    # $ovaConfiguration.Name="testesxi.corp.local"

    $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $VMName = $_.Key
        $VMIPAddress = $_.Value

        # update unique machine settings
        $ovaConfiguration.common.guestinfo.hostname.value = $VMName
        $ovaConfiguration.common.guestinfo.ipaddress.value = $VMIPAddress
        # print out the OVA settings
        $ovfconfig = $ovaConfiguration.TohashTable()
        $ovfconfig.GetEnumerator() | ForEach-Object {
            $message = 'key {0} value {1}' -f $_.key, $_.value
            Write-Host $message
        }


        # Write-Host $ovaConfiguration | Format-Custom -Depth 3
        $vm = Import-VApp -Name $VMName -Source $ovaPath -VMHost $vmhost -Datastore $datastore -OvfConfiguration $ovaConfiguration -DiskStorageFormat thin
        if ( -not $vm ) {
            throw "Nested ESXi host did not get deployed."
        }

        # update resources on new machine
        # move vmknic to correct network 
        Get-NetworkAdapter -VM $vm -Name 'vmnic0' | Set-NetworkAdapter -NetworkName $Env:EsxiMgmtNet -Confirm:$false


        # add vmnic 2 and 3
        # New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $NSXVTEPNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        # New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $NSXVTEPNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        # update VM hardware
        Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMem -confirm:$false
        Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false
        Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false
      
        # Start new Esxi hosts
        $vm | Start-Vm -RunAsync | Out-Null 
    }

}
# Deploy OVA into vCenter

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
