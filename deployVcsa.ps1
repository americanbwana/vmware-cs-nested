# Author: Dana Gertsch - @knotacoder / https://knotacoder.com
# December 2021
# Hat tip to William Lam (@lamw)
# Some code reused from https://github.com/lamw/vsphere-with-tanzu-nsxt-automated-lab-deployment
# 
# Offered As-Is.  No warranty or guarantees implied or offered.
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

# Other variables
$VAppName = "Nested-vSphere-" + $BUILDTIME
$verboseLogFile = "/var/workspace_cache/logs/vsphere-deployment-" + $BUILDTIME + ".log"

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

Write-Host "Connecting to Management vCenter Server $vCenter ..."
$viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue

# Deploy OVA into vCenter
$config = (Get-Content -Raw "/var/workspace_cache/repo/vcsa/VMware-VCSA-all-7.0.3/vcsa-cli-installer/templates/install/embedded_vCSA_on_VC.json") | convertfrom-json

if ( -not $config ) {
    throw "Could not get vcsa config file.  Maybe the path is wrong, or it didn't get downloaded."
}
# Set vcsa display name
$vcsaDisplayName = "NestedVcsa-" + $BUILDTIME

$config.'new_vcsa'.vc.hostname = $vCenter
$config.'new_vcsa'.vc.username = $vCenterUser
$config.'new_vcsa'.vc.password = $vCenterPass
$config.'new_vcsa'.vc.deployment_network = $esxiMgmtNet
$config.'new_vcsa'.vc.datastore = $vmDatastore
$config.'new_vcsa'.vc.datacenter = $vmDatacenter
$config.'new_vcsa'.vc.target = $vmCluster
$config.'new_vcsa'.appliance.thin_disk_mode = $true
$config.'new_vcsa'.appliance.deployment_option = $VCSADeploymentSize
$config.'new_vcsa'.appliance.name =$vcsaDisplayName
$config.'new_vcsa'.network.ip_family = "ipv4"
$config.'new_vcsa'.network.mode = "static"
$config.'new_vcsa'.network.ip = $vcsaIp
$config.'new_vcsa'.network.dns_servers[0] = $dnsServers
$config.'new_vcsa'.network.prefix = $esxiSubnetPrefix
$config.'new_vcsa'.network.gateway = $esxiGateway
$config.'new_vcsa'.os.ntp_servers = $ntpServers
$config.'new_vcsa'.network.system_name = $vcsaHostname
$config.'new_vcsa'.os.password = $esxiPassword
$config.'new_vcsa'.os.ssh_enable = $true
$config.'new_vcsa'.sso.password = $esxiPassword
$config.'new_vcsa'.sso.domain_name = "vsphere.local"

$config | ConvertTo-Json -Depth 4 | Set-Content -Path "/tmp/jsontemplate.json"
# save the config for future reference on pv
Write-Host "Saving a copy of the jsontemplate as /var/workspace_cache/vcsajson/NestedVcsa-$BUILDTIME.json"
$config | ConvertTo-Json -Depth 4| Set-Content -Path "/var/workspace_cache/vcsajson/NestedVcsa-$BUILDTIME.json"

# run the command to deploy the VCSA.
Write-Host "Deploying vCSA.  This will take at least 30 minutes so be patient."
Write-host "You can view the status by tailing /var/workspace_cache/logs/NestedVcsa-$BUILDTIME.log"
Invoke-Expression "/var/workspace_cache/repo/vcsa/VMware-VCSA-all-7.0.3/vcsa-cli-installer/lin64/vcsa-deploy install --no-esx-ssl-verify --accept-eula --acknowledge-ceip /tmp/jsontemplate.json"  | Out-File -Append -LiteralPath /var/workspace_cache/logs/NestedVcsa-$BUILDTIME.log

# move into vApp
$VApp = Get-VApp -Name $VAppName -Server $viConnection -Location $cluster
Write-Host "Moving $vcsaDisplayName into $VAppName vApp ..."
$vcsaVM = Get-VM -Name $vcsaDisplayName -Server $viConnection
Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
