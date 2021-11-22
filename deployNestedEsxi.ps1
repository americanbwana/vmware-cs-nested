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
$esxiOva = "Nested_ESXi7.0u3_Appliance_Template_v1.ova"

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

# General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
# Applicable to Nested ESXi only
$VMSSH = $true
$VMVMFS = $false

## Do not edit below here

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

   
Write-Host "Connecting to Management vCenter Server $vCenter ..."
Write-Host "Username $vCenterUser"
Write-Host "Pass $vCenterPass"
# $viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue
$viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenterPass 

if ( -not $viConnection ) {
    throw "Could not connect to $vCenter"
}

$datastore = Get-Datastore -Server $viConnection -Name $vmDatastore | Select -First 1
$cluster = Get-Cluster -Server $viConnection -Name $vmCluster
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1

# Add vAPP for new machines
$vApp = New-Vapp -Location $vmCluster -Name vApp-Nested-$BUILDTIME -Server $vCenter -InventoryLocation $vmFolder

if ( -not $vApp ) {
    throw "vApp was not created on " + $cluster.name
}

# /working is the entry point for the container
$ovaPath = "/working/repo/esxi/Nested_ESXi7.0u3_Appliance_Template_v1.ova"


# Now loop through $NestedESXiHostnameToIP
# Get OVA configuration
$ovaConfiguration = Get-OvfConfiguration $ovaPath
if ( -not $ovaConfiguration ) {
    throw "Could not get ovaConfiguration.  Maybe the path is wrong, or it didn't get downloaded."
}

# Change config
$ovaConfiguration.common.guestinfo.dns.value = $dnsServers
$ovaConfiguration.common.guestinfo.gateway.Value = $esxiGateway
$ovaConfiguration.common.guestinfo.ntp.value = $ntpServers
$ovaConfiguration.common.guestinfo.netmask.value = $esxiNetworkPrefix
$ovaConfiguration.common.guestinfo.domain.value = $domain
$ovaConfiguration.common.guestinfo.password.value = $esxiPassword
$ovaConfiguration.common.guestinfo.ssh.value = $VMSSH
$ovaConfiguration.common.guestinfo.createvmfs.value = $VMVMFS
$ovaConfiguration.common.guestinfo.syslog = $syslogServer

$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
    $VMName = $_.Key
    $VMIPAddress = $_.Value

    # update unique machine settings
    $ovaConfiguration.common.guestinfo.hostname.value = $VMName + "-" + $BUILDTIME + "." + $domain
    $ovaConfiguration.common.guestinfo.ipaddress.value = $VMIPAddress
    # print out the OVA settings
    $ovfconfig = $ovaConfiguration.TohashTable()
    $ovfconfig.GetEnumerator() | ForEach-Object {
        $message = 'key {0} value {1}' -f $_.key, $_.value
        Write-Host $message
    }


    # Write-Host $ovaConfiguration | Format-Custom -Depth 3
    $vm = Import-VApp -Name $VMName + "-" + $BUILDTIME + "." + $domain -Source $ovaPath -VMHost $vmhost -Datastore $datastore -OvfConfiguration $ovaConfiguration -DiskStorageFormat thin -Location $vApp
    if ( -not $vm ) {
        throw "Nested ESXi host did not get deployed."
    }

    # update resources on new machine
    # move vmknic to correct network 
    # $netAdapters = Get-NetworkAdapter -VM $vm
    Write-Host "VM adapter names $netAdapters"
    Get-NetworkAdapter -VM $vm -Name 'Network adapter 1' | Set-NetworkAdapter -NetworkName $esxiMgmtNet -Confirm:$false
    Get-NetworkAdapter -VM $vm -Name 'Network adapter 2' | Set-NetworkAdapter -NetworkName $esxiMgmtNet -Confirm:$false


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

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
