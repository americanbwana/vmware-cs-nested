# Author: Dana Gertsch - @knotacoder / https://knotacoder.com
# December 2021
# Hat tip to William Lam (@lamw)
# Some code reused from https://github.com/lamw/vsphere-with-tanzu-nsxt-automated-lab-deployment
# 
# Offered As-Is.  No warranty or guarantees implied or offered.
# Generated and saved in CS stage.
. "/working/variables.ps1"
# make sure they were imported
if (-not $vCenter) {
    throw "variable.ps1 not imported"
} else {
    Write-Host "Variables were imported, for example $vCenter"
}


$VAppName = "Nested-vSphere-" + $BUILDTIME
$verboseLogFile = "/var/workspace_cache/logs/vsphere-deployment-" + $BUILDTIME + ".log"

## Do not edit below here
## Ok, if really want to. 

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
   
Write-Host "Connecting to Management vCenter Server $vCenter ..."

$viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenterPass 

if ( -not $viConnection ) {
    throw "Could not connect to $vCenter"
} else {
    Write-Host $viConnection
}

$datastore = Get-Datastore -Server $viConnection -Name $vmDatastore | Select -First 1
$cluster = Get-Cluster -Server $viConnection -Name $vmCluster
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1

# /working is the entry point for the container
# /var/workspace_cache is the mount point for the PV
# Get OVA configuration
# Write-Host "Password from variables $nsxMgmtPassword"

## Start upload NSX manager section.
$ovaPath = "/var/workspace_cache/repo/nsxt/nsx-unified-appliance-3.1.3.3.0.18844962.ovf"
$NSXTMgrDisplayName = "Nested-NSX-" + $BUILDTIME

$nsxMgrOvfConfig = Get-OvfConfiguration $ovaPath
$nsxMgrOvfConfig.DeploymentOption.Value = "small"
$nsxMgrOvfConfig.NetworkMapping.Network_1.value = $esxiMgmtNet
$nsxMgrOvfConfig.Common.nsx_role.Value = "NSX Manager"
$nsxMgrOvfConfig.Common.nsx_hostname.Value = $NSXTMgrDisplayName
$nsxMgrOvfConfig.Common.nsx_ip_0.Value = $nsxtMgmtIpAddress
$nsxMgrOvfConfig.Common.nsx_netmask_0.Value = $esxiSubnetMask
$nsxMgrOvfConfig.Common.nsx_gateway_0.Value = $esxiGateway
$nsxMgrOvfConfig.Common.nsx_dns1_0.Value = $dnsServers
$nsxMgrOvfConfig.Common.nsx_domain_0.Value = $domain
$nsxMgrOvfConfig.Common.nsx_ntp_0.Value = $ntpServers
$nsxMgrOvfConfig.Common.nsx_isSSHEnabled.Value = $true
$nsxMgrOvfConfig.Common.nsx_allowSSHRootLogin.Value = $true
$nsxMgrOvfConfig.Common.nsx_passwd_0.Value = $nsxMgmtPassword
$nsxMgrOvfConfig.Common.nsx_cli_username.Value = $nsxMgmtPassword
$nsxMgrOvfConfig.Common.nsx_cli_passwd_0.Value = $nsxMgmtPassword
$nsxMgrOvfConfig.Common.nsx_cli_audit_username.Value = $nsxMgmtPassword
$nsxMgrOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $nsxMgmtPassword

# print out the OVA settings
$ovfconfig = $nsxMgrOvfConfig.TohashTable()
$ovfconfig.GetEnumerator() | ForEach-Object {
    $message = 'key {0} value {1}' -f $_.key, $_.value
    Write-Host $message
}

Write-Host "Deploying NSX Manager VM $NSXTMgrDisplayName ..."

$nsxmgr_vm = Import-VApp -Source $ovaPath -OvfConfiguration $nsxMgrOvfConfig -Name $NSXTMgrDisplayName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

Write-Host "Updating vCPU Count to 6 & vMEM to 24 GB ..."
Set-VM -Server $viConnection -VM $nsxmgr_vm -NumCpu 6 -MemoryGB 24 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

Write-Host "Disabling vCPU Reservation ..."
Get-VM -Server $viConnection -Name $nsxmgr_vm | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0 | Out-File -Append -LiteralPath $verboseLogFile

Write-Host "Powering On $NSXTMgrDisplayName ..."
$nsxmgr_vm | Start-Vm -RunAsync | Out-Null

## End upload NSX 
# Move NSX Manager into vAPP

Write-Host "Moving Nested NSXT VM into $VAppName vApp ..."
$VApp = Get-VApp -Name $VAppName -Server $viConnection -Location $cluster
Write-Host "Moving $NSXTMgrDisplayName into $VAppName vApp ..."
$vcsaVM = Get-VM -Name $NSXTMgrDisplayName -Server $viConnection
Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
