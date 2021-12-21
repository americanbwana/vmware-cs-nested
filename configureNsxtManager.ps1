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
Function Get-SSLThumbprint {
    param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [Alias('FullName')]
    [String]$URL
    )

    $Code = @'
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
namespace CertificateCapture
{
    public class Utility
    {
        public static Func<HttpRequestMessage,X509Certificate2,X509Chain,SslPolicyErrors,Boolean> ValidationCallback =
            (message, cert, chain, errors) => {
                var newCert = new X509Certificate2(cert);
                var newChain = new X509Chain();
                newChain.Build(newCert);
                CapturedCertificates.Add(new CapturedCertificate(){
                    Certificate =  newCert,
                    CertificateChain = newChain,
                    PolicyErrors = errors,
                    URI = message.RequestUri
                });
                return true;
            };
        public static List<CapturedCertificate> CapturedCertificates = new List<CapturedCertificate>();
    }
    public class CapturedCertificate
    {
        public X509Certificate2 Certificate { get; set; }
        public X509Chain CertificateChain { get; set; }
        public SslPolicyErrors PolicyErrors { get; set; }
        public Uri URI { get; set; }
    }
}
'@
    if ($PSEdition -ne 'Core'){
        Add-Type -AssemblyName System.Net.Http
        if (-not ("CertificateCapture" -as [type])) {
            try { Add-Type $Code -ReferencedAssemblies System.Net.Http } catch {}
        }
    } else {
        if (-not ("CertificateCapture" -as [type])) {
            try { Add-Type $Code -ErrorAction SilentlyContinue } catch {}
        }
    }

    $Certs = [CertificateCapture.Utility]::CapturedCertificates

    $Handler = [System.Net.Http.HttpClientHandler]::new()
    $Handler.ServerCertificateCustomValidationCallback = [CertificateCapture.Utility]::ValidationCallback
    $Client = [System.Net.Http.HttpClient]::new($Handler)
    $Result = $Client.GetAsync($Url).Result

    $sha1 = [Security.Cryptography.SHA1]::Create()
    $certBytes = $Certs[-1].Certificate.GetRawCertData()
    $hash = $sha1.ComputeHash($certBytes)
    $thumbprint = [BitConverter]::ToString($hash).Replace('-',':')
    return $thumbprint.toLower()
}

Function Get-SSLThumbprint256 {
    param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [Alias('FullName')]
    [String]$URL
    )

    $Code = @'
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

namespace CertificateCapture
{
    public class Utility
    {
        public static Func<HttpRequestMessage,X509Certificate2,X509Chain,SslPolicyErrors,Boolean> ValidationCallback =
            (message, cert, chain, errors) => {
                var newCert = new X509Certificate2(cert);
                var newChain = new X509Chain();
                newChain.Build(newCert);
                CapturedCertificates.Add(new CapturedCertificate(){
                    Certificate =  newCert,
                    CertificateChain = newChain,
                    PolicyErrors = errors,
                    URI = message.RequestUri
                });
                return true;
            };
        public static List<CapturedCertificate> CapturedCertificates = new List<CapturedCertificate>();
    }

    public class CapturedCertificate
    {
        public X509Certificate2 Certificate { get; set; }
        public X509Chain CertificateChain { get; set; }
        public SslPolicyErrors PolicyErrors { get; set; }
        public Uri URI { get; set; }
    }
}
'@
    if ($PSEdition -ne 'Core'){
        Add-Type -AssemblyName System.Net.Http
        if (-not ("CertificateCapture" -as [type])) {
            try { Add-Type $Code -ReferencedAssemblies System.Net.Http } catch {}
        }
    } else {
        if (-not ("CertificateCapture" -as [type])) {
            try { Add-Type $Code -ErrorAction SilentlyContinue } catch {}
        }
    }

    $Certs = [CertificateCapture.Utility]::CapturedCertificates

    $Handler = [System.Net.Http.HttpClientHandler]::new()
    $Handler.ServerCertificateCustomValidationCallback = [CertificateCapture.Utility]::ValidationCallback
    $Client = [System.Net.Http.HttpClient]::new($Handler)
    $Result = $Client.GetAsync($Url).Result

    $sha256 = [Security.Cryptography.SHA256]::Create()
    $certBytes = $Certs[-1].Certificate.GetRawCertData()
    $hash = $sha256.ComputeHash($certBytes)
    $thumbprint = [BitConverter]::ToString($hash).Replace('-',':')
    return $thumbprint
}


# Transport Node Profile
$TransportNodeProfileName = "Tanzu-Host-Transport-Node-Profile"

# TEP IP Pool
$TunnelEndpointName = "TEP-IP-Pool"
$TunnelEndpointDescription = "Tunnel Endpoint for Transport Nodes"
$TunnelEndpointIPRangeStart = "172.25.2.10"
$TunnelEndpointIPRangeEnd = "172.25.2.29"
$TunnelEndpointCIDR = "172.25.2.0/24"
$TunnelEndpointGateway = "172.25.2.1"

# Transport Zones
$OverlayTransportZoneName = "TZ-Overlay"
$OverlayTransportZoneHostSwitchName = "nsxswitch"
$VlanTransportZoneName = "TZ-VLAN"
$VlanTransportZoneNameHostSwitchName = "edgeswitch"

# Network Segment
$NetworkSegmentName = "Tanzu-Segment"
$NetworkSegmentVlan = "0"

# T0 Gateway
$T0GatewayName = "Tanzu-T0-Gateway"
$T0GatewayInterfaceAddress = "172.25.2.30" # should be a routable address
$T0GatewayInterfacePrefix = "24"
$T0GatewayInterfaceStaticRouteName = "Tanzu-Static-Route"
$T0GatewayInterfaceStaticRouteNetwork = "0.0.0.0/0"
$T0GatewayInterfaceStaticRouteAddress = "172.25.2.1"

# Uplink Profiles
$ESXiUplinkProfileName = "ESXi-Host-Uplink-Profile"
$ESXiUplinkProfilePolicy = "FAILOVER_ORDER"
$ESXiUplinkName = "uplink1"
$ESXiUplinkProfileTransportVLAN = "0"

$EdgeUplinkProfileName = "Edge-Uplink-Profile"
$EdgeUplinkProfilePolicy = "FAILOVER_ORDER"
$EdgeOverlayUplinkName = "uplink1"
$EdgeOverlayUplinkProfileActivepNIC = "fp-eth1"
$EdgeUplinkName = "tep-uplink"
$EdgeUplinkProfileActivepNIC = "fp-eth2"
$EdgeUplinkProfileTransportVLAN = "0"
$EdgeUplinkProfileMTU = "1600"

# Edge Cluster
$EdgeClusterName = "Edge-Cluster-01"


# NSX-T Edge Configuration
$NSXTEdgeDeploymentSize = "medium"
$NSXTEdgevCPU = "8" #override default size
$NSXTEdgevMEM = "32" #override default size
$NSXTEdgeHostnameToIPs = @{
    "tanzu-nsx-edge-3a" = "172.25.1.31"
}

# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
   
# Write-Host "Connecting to Management vCenter Server $vCenter ..."

# $viConnection = Connect-VIServer $vCenter -User $vCenterUser -Password $vCenterPass 

# if ( -not $viConnection ) {
#     throw "Could not connect to $vCenter"
# } else {
#     Write-Host $viConnection
# }

## from WL code 
Write-Host "Connecting to NSX-T Manager for post-deployment configuration ..."
if(!(Connect-NsxtServer -Server $nsxtMgmtIpAddress -Username admin -Password $nsxMgmtPassword -WarningAction SilentlyContinue)) {
    Write-Host -ForegroundColor Red "Unable to connect to NSX-T Manager, please check the deployment"
    exit
} else {
    Write-Host "Successfully logged into NSX-T Manager $nsxMgmtIPAddress  ..."
}


Write-Host "Verifying health of all NSX Manager/Controller Nodes ..."
$clusterNodeService = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes"
$clusterNodeStatusService = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes.status"
$nodes = $clusterNodeService.list().results
$mgmtNodes = $nodes | where { $_.controller_role -eq $null }
$controllerNodes = $nodes | where { $_.manager_role -eq $null }

foreach ($mgmtNode in $mgmtNodes) {
    $mgmtNodeId = $mgmtNode.id
    $mgmtNodeName = $mgmtNode.appliance_mgmt_listen_addr

    if($debug) { Write-Host "Check health status of Mgmt Node $mgmtNodeName ..." }
    while ( $clusterNodeStatusService.get($mgmtNodeId).mgmt_cluster_status.mgmt_cluster_status -ne "CONNECTED") {
        if($debug) { Write-Host "$mgmtNodeName is not ready, sleeping 20 seconds ..." }
        Start-Sleep 20
    }
}

foreach ($controllerNode in $controllerNodes) {
    $controllerNodeId = $controllerNode.id
    $controllerNodeName = $controllerNode.controller_role.control_plane_listen_addr.ip_address

    if($debug) { Write-Host "Checking health of Ctrl Node $controllerNodeName ..." }
    while ( $clusterNodeStatusService.get($controllerNodeId).control_cluster_status.control_cluster_status -ne "CONNECTED") {
        if($debug) { Write-Host "$controllerNodeName is not ready, sleeping 20 seconds ..." }
        Start-Sleep 20
    }
}



Write-Host "Accepting CEIP Agreement ..."
$ceipAgreementService = Get-NsxtService -Name "com.vmware.nsx.telemetry.agreement"
$ceipAgreementSpec = $ceipAgreementService.get()
$ceipAgreementSpec.telemetry_agreement_displayed = $true
$agreementResult = $ceipAgreementService.update($ceipAgreementSpec)


Write-Host "Adding vCenter Server Compute Manager ..."
$computeManagerService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_managers"
$computeManagerStatusService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_managers.status"

$computeManagerSpec = $computeManagerService.help.create.compute_manager.Create()
$credentialSpec = $computeManagerService.help.create.compute_manager.credential.username_password_login_credential.Create()
$VCURL = "https://" + $vcsaName + ":443"
$VCThumbprint = Get-SSLThumbprint256 -URL $VCURL
$credentialSpec.username = "administrator@vsphere.local"
$credentialSpec.password = $esxiPassword
$credentialSpec.thumbprint = $VCThumbprint
$computeManagerSpec.server = $vcsaName
$computeManagerSpec.origin_type = "vCenter"
$computeManagerSpec.display_name = $vcsaName
$computeManagerSpec.credential = $credentialSpec
$computeManagerSpec.create_service_account = $true
$computeManagerSpec.set_as_oidc_provider = $true
$computeManagerResult = $computeManagerService.create($computeManagerSpec)

if($debug) { Write-Host "Waiting for VC registration to complete ..." }
    while ( $computeManagerStatusService.get($computeManagerResult.id).registration_status -ne "REGISTERED") {
        if($debug) { Write-Host "$vcsaName is not ready, sleeping 30 seconds ..." }
        Start-Sleep 30
}

Write-Host "Creating Tunnel Endpoint IP Pool ..."
$ipPoolService = Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools"
$ipPoolSpec = $ipPoolService.help.create.ip_pool.Create()
$subNetSpec = $ipPoolService.help.create.ip_pool.subnets.Element.Create()
$allocationRangeSpec = $ipPoolService.help.create.ip_pool.subnets.Element.allocation_ranges.Element.Create()

$allocationRangeSpec.start = $TunnelEndpointIPRangeStart
$allocationRangeSpec.end = $TunnelEndpointIPRangeEnd
$addResult = $subNetSpec.allocation_ranges.Add($allocationRangeSpec)
$subNetSpec.cidr = $TunnelEndpointCIDR
$subNetSpec.gateway_ip = $TunnelEndpointGateway
$ipPoolSpec.display_name = $TunnelEndpointName
$ipPoolSpec.description = $TunnelEndpointDescription
$addResult = $ipPoolSpec.subnets.Add($subNetSpec)
$ipPool = $ipPoolService.create($ipPoolSpec)



Write-Host "Creating Overlay & VLAN Transport Zones ..."

$transportZoneService = Get-NsxtService -Name "com.vmware.nsx.transport_zones"
$overlayTZSpec = $transportZoneService.help.create.transport_zone.Create()
$overlayTZSpec.display_name = $OverlayTransportZoneName
$overlayTZSpec.host_switch_name = $OverlayTransportZoneHostSwitchName
$overlayTZSpec.transport_type = "OVERLAY"
$overlayTZ = $transportZoneService.create($overlayTZSpec)

$vlanTZSpec = $transportZoneService.help.create.transport_zone.Create()
$vlanTZSpec.display_name = $VLANTransportZoneName
$vlanTZSpec.host_switch_name = $VlanTransportZoneNameHostSwitchName
$vlanTZSpec.transport_type = "VLAN"
$vlanTZ = $transportZoneService.create($vlanTZSpec)



$hostSwitchProfileService = Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles"

Write-Host "Creating ESXi Uplink Profile ..."
$ESXiUplinkProfileSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.Create()
$activeUplinkSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.teaming.active_list.Element.Create()
$activeUplinkSpec.uplink_name = $ESXiUplinkName
$activeUplinkSpec.uplink_type = "PNIC"
$ESXiUplinkProfileSpec.display_name = $ESXiUplinkProfileName
$ESXiUplinkProfileSpec.transport_vlan = $ESXiUplinkProfileTransportVLAN
$addActiveUplink = $ESXiUplinkProfileSpec.teaming.active_list.Add($activeUplinkSpec)
$ESXiUplinkProfileSpec.teaming.policy = $ESXiUplinkProfilePolicy
$ESXiUplinkProfile = $hostSwitchProfileService.create($ESXiUplinkProfileSpec)

Write-Host "Creating Edge Uplink Profile ..."
$EdgeUplinkProfileSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.Create()
$activeUplinkSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.teaming.active_list.Element.Create()
$activeUplinkSpec.uplink_name = $EdgeUplinkName
$activeUplinkSpec.uplink_type = "PNIC"
$EdgeUplinkProfileSpec.display_name = $EdgeUplinkProfileName
$EdgeUplinkProfileSpec.mtu = $EdgeUplinkProfileMTU
$EdgeUplinkProfileSpec.transport_vlan = $EdgeUplinkProfileTransportVLAN
$addActiveUplink = $EdgeUplinkProfileSpec.teaming.active_list.Add($activeUplinkSpec)
$EdgeUplinkProfileSpec.teaming.policy = $EdgeUplinkProfilePolicy
$EdgeUplinkProfile = $hostSwitchProfileService.create($EdgeUplinkProfileSpec)

$vc = Connect-VIServer $vcsaIp -User "administrator@vsphere.local" -Password $esxiPassword -WarningAction SilentlyContinue

    # Retrieve VDS UUID from vCenter Server
    $VDS = (Get-VDSwitch -Server $vc -Name "DVSwitch").ExtensionData
    $VDSUuid = $VDS.Uuid
    Disconnect-VIServer $vc -Confirm:$false

    $hostswitchProfileService = Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles"

    $ipPool = (Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools").list().results | where { $_.display_name -eq $TunnelEndpointName }
    $OverlayTZ = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.display_name -eq $OverlayTransportZoneName }
    $ESXiUplinkProfile = $hostswitchProfileService.list().results | where { $_.display_name -eq $ESXiUplinkProfileName }

    $esxiIpAssignmentSpec = [pscustomobject] @{
        "resource_type" = "StaticIpPoolSpec";
        "ip_pool_id" = $ipPool.id;
    }

    $edgeIpAssignmentSpec = [pscustomobject] @{
        "resource_type" = "AssignedByDhcp";
    }

    $hostTransportZoneEndpoints = @(@{"transport_zone_id"=$OverlayTZ.id})

    $esxiHostswitchSpec = [pscustomobject] @{
        "host_switch_name" = $OverlayTransportZoneHostSwitchName;
        "host_switch_mode" = "STANDARD";
        "host_switch_type" = "VDS";
        "host_switch_id" = $VDSUuid;
        "uplinks" = @(@{"uplink_name"=$ESXiUplinkName;"vds_uplink_name"=$ESXiUplinkName})
        "ip_assignment_spec" = $esxiIpAssignmentSpec;
        "host_switch_profile_ids" = @(@{"key"="UplinkHostSwitchProfile";"value"=$ESXiUplinkProfile.id})
        "transport_zone_endpoints" = $hostTransportZoneEndpoints;
    }

    $json = [pscustomobject] @{
        "resource_type" = "TransportNode";
        "display_name" = $TransportNodeProfileName;
        "host_switch_spec" = [pscustomobject] @{
            "host_switches" = @($esxiHostswitchSpec)
            "resource_type" = "StandardHostSwitchSpec";
        }
    }

    $body = $json | ConvertTo-Json -Depth 10

    $pair = "admin:${nsxMgmtPassword}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)

    $headers = @{
        "Authorization"="basic $base64"
        "Content-Type"="application/json"
        "Accept"="application/json"
    }

    $transportNodeUrl = "https://$nsxtMgmtIpAddress/api/v1/transport-node-profiles"

    if($debug) {
        "URL: $transportNodeUrl" | Out-File -Append -LiteralPath $verboseLogFile
        "Headers: $($headers | Out-String)" | Out-File -Append -LiteralPath $verboseLogFile
        "Body: $body" | Out-File -Append -LiteralPath $verboseLogFile
    }

    try {
        Write-Host "Creating Transport Node Profile $TransportNodeProfileName ..."
        if($PSVersionTable.PSEdition -eq "Core") {
            $requests = Invoke-WebRequest -Uri $transportNodeUrl -Body $body -Method POST -Headers $headers -SkipCertificateCheck
        } else {
            $requests = Invoke-WebRequest -Uri $transportNodeUrl -Body $body -Method POST -Headers $headers
        }
    } catch {
        Write-Error "Error in creating NSX-T Transport Node Profile"
        Write-Error "`n($_.Exception.Message)`n"
        break
    }

    if($requests.StatusCode -eq 201) {
        Write-Host "Successfully Created Transport Node Profile"
    } else {
        Write-Host "Unknown State: $requests"
    }
##
    $transportNodeCollectionService = Get-NsxtService -Name "com.vmware.nsx.transport_node_collections"
    $transportNodeCollectionStateService = Get-NsxtService -Name "com.vmware.nsx.transport_node_collections.state"
    $computeCollectionService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_collections"
    $transportNodeProfileService = Get-NsxtService -Name "com.vmware.nsx.transport_node_profiles"

    $computeCollectionId = ($computeCollectionService.list().results | where {$_.display_name -eq "CL1"}).external_id
    $transportNodeProfileId = ($transportNodeProfileService.list().results | where {$_.display_name -eq $TransportNodeProfileName}).id

    $transportNodeCollectionSpec = $transportNodeCollectionService.help.create.transport_node_collection.Create()
    $transportNodeCollectionSpec.display_name = "ESXi Transport Node Collection"
    $transportNodeCollectionSpec.compute_collection_id = $computeCollectionId
    $transportNodeCollectionSpec.transport_node_profile_id = $transportNodeProfileId
    Write-Host "Applying Transport Node Profile to ESXi Transport Nodes ..."
    $transportNodeCollection = $transportNodeCollectionService.create($transportNodeCollectionSpec)

    Write-Host "Waiting for ESXi transport node configurations to complete ..."
    while ( $transportNodeCollectionStateService.get(${transportNodeCollection}.id).state -ne "SUCCESS") {
        $percent = $transportNodeCollectionStateService.get(${transportNodeCollection}.id).aggregate_progress_percentage
        if($debug) { Write-Host "ESXi transport node is still being configured (${percent}% Completed), sleeping for 30 seconds ..." }
        Start-Sleep 30
    }

    $transportNodeService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes"
    $hostswitchProfileService = Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles"
    $transportNodeStateService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes.state"

    # Retrieve all Edge Host Nodes
    # $edgeNodes = $transportNodeService.list().results | where {$_.node_deployment_info.resource_type -eq "EdgeNode"}
    # $ipPool = (Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools").list().results | where { $_.display_name -eq $TunnelEndpointName }
    # $OverlayTZ = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.display_name -eq $OverlayTransportZoneName }
    # $VlanTZ = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.display_name -eq $VlanTransportZoneName }
    # $ESXiUplinkProfile = $hostswitchProfileService.list().results | where { $_.display_name -eq $ESXiUplinkProfileName }
    # $EdgeUplinkProfile = $hostswitchProfileService.list().results | where { $_.display_name -eq $EdgeUplinkProfileName }
    # $NIOCProfile = $hostswitchProfileService.list($null,"VIRTUAL_MACHINE","NiocProfile",$true,$null,$null,$null).results | where {$_.display_name -eq "nsx-default-nioc-hostswitch-profile"}
    # $LLDPProfile = $hostswitchProfileService.list($null,"VIRTUAL_MACHINE","LldpHostSwitchProfile",$true,$null,$null,$null).results | where {$_.display_name -eq "LLDP [Send Packet Enabled]"}

    # foreach ($edgeNode in $edgeNodes) {
    #     $overlayIpAssignmentSpec = [pscustomobject] @{
    #         "resource_type" = "StaticIpPoolSpec";
    #         "ip_pool_id" = $ipPool.id;
    #     }

    #     $edgeIpAssignmentSpec = [pscustomobject] @{
    #         "resource_type" = "AssignedByDhcp";
    #     }

    #     $OverlayTransportZoneEndpoints = @(@{"transport_zone_id"=$OverlayTZ.id})
    #     $EdgeTransportZoneEndpoints = @(@{"transport_zone_id"=$VlanTZ.id})

    #     $overlayHostswitchSpec = [pscustomobject]  @{
    #         "host_switch_name" = $OverlayTransportZoneHostSwitchName;
    #         "host_switch_mode" = "STANDARD";
    #         "ip_assignment_spec" = $overlayIpAssignmentSpec
    #         "pnics" = @(@{"device_name"=$EdgeOverlayUplinkProfileActivepNIC;"uplink_name"=$EdgeOverlayUplinkName;})
    #         "host_switch_profile_ids" = @(@{"key"="UplinkHostSwitchProfile";"value"=$ESXiUplinkProfile.id})
    #         "transport_zone_endpoints" = $OverlayTransportZoneEndpoints;
    #     }

    #     $edgeHostswitchSpec = [pscustomobject]  @{
    #         "host_switch_name" = $VlanTransportZoneNameHostSwitchName;
    #         "host_switch_mode" = "STANDARD";
    #         "pnics" = @(@{"device_name"=$EdgeUplinkProfileActivepNIC;"uplink_name"=$EdgeUplinkName;})
    #         "ip_assignment_spec" = $edgeIpAssignmentSpec
    #         "host_switch_profile_ids" = @(@{"key"="UplinkHostSwitchProfile";"value"=$EdgeUplinkProfile.id})
    #         "transport_zone_endpoints" = $EdgeTransportZoneEndpoints;
    #     }

    #     $json = [pscustomobject] @{
    #         "resource_type" = "TransportNode";
    #         "node_id" = $edgeNode.node_id;
    #         "display_name" = $edgeNode.display_name;
    #         "host_switch_spec" = [pscustomobject] @{
    #             "host_switches" = @($overlayHostswitchSpec,$edgeHostswitchSpec)
    #             "resource_type" = "StandardHostSwitchSpec";
    #         };
    #     }

    #     $body = $json | ConvertTo-Json -Depth 10

    #     $pair = "${NSXAdminUsername}:${NSXAdminPassword}"
    #     $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    #     $base64 = [System.Convert]::ToBase64String($bytes)

    #     $headers = @{
    #         "Authorization"="basic $base64"
    #         "Content-Type"="application/json"
    #         "Accept"="application/json"
    #     }

    #     $transportNodeUrl = "https://$NSXTMgrHostname/api/v1/transport-nodes"

    #     # try {
    #     #     Write-Host "Creating NSX-T Edge Transport Node for $($edgeNode.display_name) ..."
    #     #     if($PSVersionTable.PSEdition -eq "Core") {
    #     #         $requests = Invoke-WebRequest -Uri $transportNodeUrl -Body $body -Method POST -Headers $headers -SkipCertificateCheck
    #     #     } else {
    #     #         $requests = Invoke-WebRequest -Uri $transportNodeUrl -Body $body -Method POST -Headers $headers
    #     #     }
    #     # } catch {
    #     #     Write-Error "Error in creating NSX-T Edge Transport Node"
    #     #     Write-Error "`n($_.Exception.Message)`n"
    #     #     break
    #     }

    #     # if($requests.StatusCode -eq 201) {
    #     #     Write-Host "Successfully Created NSX-T Edge Transport Node "
    #     #     $edgeTransPortNodeId = ($requests.Content | ConvertFrom-Json).node_id
    #     # } else {
    #     #     Write-Host "Unknown State: $requests"
    #     #     break
    #     # }

    # #    Write-Host "Waiting for Edge transport node configurations to complete ..."
    # #     while ($transportNodeStateService.get($edgeTransPortNodeId).state -ne "success") {
    # #         if($debug) { Write-Host "Edge transport node is still being configured, sleeping for 30 seconds ..." }
    # #         Start-Sleep 30
    # #     } 



    # $edgeNodes = (Get-NsxtService -Name "com.vmware.nsx.fabric.nodes").list().results | where { $_.resource_type -eq "EdgeNode" }
    # $edgeClusterService = Get-NsxtService -Name "com.vmware.nsx.edge_clusters"
    # $edgeClusterStateService = Get-NsxtService -Name "com.vmware.nsx.edge_clusters.state"
    # $edgeNodeMembersSpec = $edgeClusterService.help.create.edge_cluster.members.Create()

    # Write-Host "Creating Edge Cluster $EdgeClusterName and adding Edge Hosts ..."

    # foreach ($edgeNode in $edgeNodes) {
    #     $edgeNodeMemberSpec = $edgeClusterService.help.create.edge_cluster.members.Element.Create()
    #     $edgeNodeMemberSpec.transport_node_id = $edgeNode.id
    #     $edgeNodeMemberAddResult = $edgeNodeMembersSpec.Add($edgeNodeMemberSpec)
    # }

    # $edgeClusterSpec = $edgeClusterService.help.create.edge_cluster.Create()
    # $edgeClusterSpec.display_name = $EdgeClusterName
    # $edgeClusterSpec.members = $edgeNodeMembersSpec
    # $edgeCluster = $edgeClusterService.Create($edgeClusterSpec)

    # $edgeState = $edgeClusterStateService.get($edgeCluster.id)
    # $maxCount=5
    # $count=0
    # while($edgeState.state -ne "in_sync") {
    #     Write-Host "Edge Cluster has not been realized, sleeping for 10 seconds ..."
    #     Start-Sleep -Seconds 10
    #     $edgeState = $edgeClusterStateService.get($edgeCluster.id)

    #     if($count -eq $maxCount) {
    #         Write-Host "Edge Cluster has not been realized! exiting ..."
    #         break
    #     } else {
    #         $count++
    #     }
    # }
    # # Need to force Policy API sync to ensure Edge Cluster details are available for later use
    # $reloadOp = (Get-NsxtPolicyService -Name "com.vmware.nsx_policy.infra.sites.enforcement_points").reload("default","default")
    # Write-Host "Edge Cluster has been realized"

