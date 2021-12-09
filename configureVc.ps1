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
# Add variables

# From WL
$NestedESXiHostnameToIPs = @{
    $Esxi01Name = $Esxi01Ip
    $Esxi02Name = $Esxi02Ip
    $Esxi03Name = $Esxi03Ip
}

$verboseLogFile = "/var/workspace_cache/logs/vsphere-deployment-" + $BUILDTIME + ".log"

$NestedESXiCachingvDisk = "8" #GB
$NestedESXiCapacityvDisk = "100" #GB

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Configure vCenter
Write-Host "Connecting to the new VCSA ..."
$vc = Connect-VIServer $vcsaHostname -User "administrator@vsphere.local" -Password $esxiPassword -WarningAction SilentlyContinue

$d = Get-Datacenter -Server $vc DC -ErrorAction Ignore
if( -Not $d) {
    Write-Host "Creating Datacenter DC ..."
    New-Datacenter -Server $vc -Name DC -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
}

$c = Get-Cluster -Server $vc CL1 -ErrorAction Ignore
if( -Not $c) {

    Write-Host "Creating VSAN Cluster VLANCluster ..."
    New-Cluster -Server $vc -Name CL1 -Location (Get-Datacenter -Name DC -Server $vc) -DrsEnabled -HAEnabled -VsanEnabled | Out-File -Append -LiteralPath $verboseLogFile

(Get-Cluster CL1) | New-AdvancedSetting -Name "das.ignoreRedundantNetWarning" -Type ClusterHA -Value $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
}

# Add hosts to cluster
$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
    $VMName = $_.Key
    $VMIPAddress = $_.Value

    $targetVMHost = $VMIPAddress
    # Make sure the Esxi deployment network allow promiscuous mode
    # Otherwise this may fail

    Write-Host "Adding ESXi host $targetVMHost to Cluster ..."
    Add-VMHost -Server $vc -Location (Get-Cluster -Name CL1 ) -User "root" -Password $esxiPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
}

Write-Host "Enabling VSAN & disabling VSAN Health Check ..."
Get-VsanClusterConfiguration -Server $vc -Cluster CL1 | Set-VsanClusterConfiguration -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile

foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
    $luns = $vmhost | Get-ScsiLun | select CanonicalName, CapacityGB

    Write-Host "Querying ESXi host disks to create VSAN Diskgroups ..."
    foreach ($lun in $luns) {
        if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCachingvDisk") {
            $vsanCacheDisk = $lun.CanonicalName
        }
        if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCapacityvDisk") {
            $vsanCapacityDisk = $lun.CanonicalName
        }
    }
    Write-Host "Creating VSAN DiskGroup for $vmhost ..."
    New-VsanDiskGroup -Server $vc -VMHost $vmhost -SsdCanonicalName $vsanCacheDisk -DataDiskCanonicalName $vsanCapacityDisk | Out-File -Append -LiteralPath $verboseLogFile
}

# Apply VSAN configuration to CL1. 
Set-VsanClusterConfiguration -Configuration "CL1" -AddSilentHealthCheck controlleronhcl,vumconfig,vumrecommendation -PerformanceServiceEnabled $true


# Final configure and then exit maintanence mode in case patching was done earlier
foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
    # Disable Core Dump Warning
    Get-AdvancedSetting -Entity $vmhost -Name UserVars.SuppressCoredumpWarning | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    # Enable vMotion traffic
    $vmhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    if($vmhost.ConnectionState -eq "Maintenance") {
        Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
}
# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
