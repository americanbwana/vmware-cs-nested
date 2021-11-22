# import from variable file 
# Generated and saved in CS stage.
. "/working/variables.ps1"
# make sure they were imported
if (-not $vCenter) {
    throw "variable.ps1 not imported"
} else {
    Write-Host "Variables were imported, for example $vCenter"
}

# VCSA Deployment Configuration
$VCSADeploymentSize = "tiny"


# General Deployment Configuration for Nested ESXi, VCSA & NSX VMs

## Do not edit below here

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false


Write-Host "Connecting to Management vCenter Server $vCenter ..."
$viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenter -WarningAction SilentlyContinue

$datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
$cluster = Get-Cluster -Server $viConnection -Name $VMCluster
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1

$vApp = Get-Vapp -Server $vCenter -Name vApp-Nested-$BUILDTIME

if ( -not $vApp ) {
    Write-Host "Could not find vApp in -Name vApp-Nested-$BUILDTIME"
}

# Deploy OVA into vCenter
# /working/repo/vcsa/VMware-VCSA-all-7.0.3/
$config = (Get-Content -Raw "/working/repo/vcsa/VMware-VCSA-all-7.0.3/vcsa-cli-installer/templates/install/embedded_vCSA_on_VC.json") | convertfrom-json

if ( -not $config ) {
    throw "Could not get vcsa config file.  Maybe the path is wrong, or it didn't get downloaded."
}

$config.'new_vcsa'.vc.hostname = $vCenter
$config.'new_vcsa'.vc.username = $vCenterUser
$config.'new_vcsa'.vc.password = $vCenterPass
$config.'new_vcsa'.vc.deployment_network = $esxiMgmtNet
$config.'new_vcsa'.vc.datastore = $vmDatastore
$config.'new_vcsa'.vc.datacenter = $datacenter.name
$config.'new_vcsa'.vc.target = $vmCluster
$config.'new_vcsa'.appliance.thin_disk_mode = $true
$config.'new_vcsa'.appliance.deployment_option = $VCSADeploymentSize
$config.'new_vcsa'.appliance.name = "NestedVcsa-" + $BUILDTIME
$config.'new_vcsa'.network.ip_family = "ipv4"
$config.'new_vcsa'.network.mode = "static"
$config.'new_vcsa'.network.ip = $vcsaIp
$config.'new_vcsa'.network.dns_servers[0] = $ntpServers
$config.'new_vcsa'.network.prefix = $esxiSubnetPrefix
$config.'new_vcsa'.network.gateway = $esxiGateway
$config.'new_vcsa'.os.ntp_servers = $ntpServers
$config.'new_vcsa'.network.system_name = $vcsaHostname
$config.'new_vcsa'.os.password = $esxiPassword
$config.'new_vcsa'.os.ssh_enable = $true
$config.'new_vcsa'.sso.password = $esxiPassword
$config.'new_vcsa'.sso.domain_name = "vsphere.local"

$config | ConvertTo-Json | Set-Content -Path "/tmp/jsontemplate.json"

Invoke-Expression "/working/repo/vcsa/VMware-VCSA-all-7.0.3//vcsa-cli-installer/lin64/vcsa-deploy install --no-esx-ssl-verify --accept-eula --acknowledge-ceip /tmp/jsontemplate.json"

# $vcsaVM = Get-VM -Name $VCSADisplayName -Server $viConnection
# My-Logger "Moving $VCSADisplayName into $VAppName vApp ..."
# Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
