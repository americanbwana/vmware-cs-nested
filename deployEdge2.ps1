# Author: Dana Gertsch - @knotacoder / https://knotacoder.com
# Jan 2022
# Hat tip to William Lam (@lamw)
# Some code reused from https://github.com/lamw/vsphere-with-tanzu-nsxt-automated-lab-deployment
# 
# Offered As-Is.  No warranty or guarantees implied or offered.
# Generated and saved in CS stage.
# This uses direct NSXT api calls as the CONNECT-NSXTMANAGER cmdlet times out in a container
# 
. "/working/variables.ps1"
# . "./variables.ps1"
# make sure they were imported
if (-not $vCenter) {
    throw "variable.ps1 not imported"
} else {
    Write-Host "Variables were imported, for example $vCenter"
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
$verboseLogFile = "/var/workspace_cache/logs/vsphere-deployment-" + $BUILDTIME + ".log"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
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

$ovaPath = "/var/workspace_cache/repo/edge/nsx-edge-3.1.3.3.0.18844966.ovf"

$EdgeDisplayName = "Nested-Edge-" + $BUILDTIME


# NSX-T Edge Configuration
$NSXTEdgeDeploymentSize = "medium"
$NSXTEdgevCPU = "8" #override default size
$NSXTEdgevMEM = "32" #override default size
# $NSXTEdgeHostnameToIPs = @{
#     "tanzu-nsx-edge-3a" = "172.17.31.116"
# }
# need thumbprint
$VCURL = "https://" + $nsxtMgmtIpAddress + ":443"
$nsxMgrCertThumbprint = Get-SSLThumbprint256 -URL $VCURL
# Get Edge OVF config

$nsxEdgeOvfConfig = Get-OvfConfiguration $ovaPath 

$vmname = "Nested-Edge-" + $BUILDTIME

$VMHostname = "$vmname" + "." + $domain

$nsxEdgeOvfConfig.DeploymentOption.Value = $NSXTEdgeDeploymentSize
$nsxEdgeOvfConfig.NetworkMapping.Network_0.value = $VMNetwork
$nsxEdgeOvfConfig.NetworkMapping.Network_1.value = $NSXVTEPNetwork
$nsxEdgeOvfConfig.NetworkMapping.Network_2.value = $VMNetwork
$nsxEdgeOvfConfig.NetworkMapping.Network_3.value = $VMNetwork

$nsxEdgeOvfConfig.Common.nsx_hostname.Value = $VMHostname
$nsxEdgeOvfConfig.Common.nsx_ip_0.Value = $edgeIpAddress
$nsxEdgeOvfConfig.Common.nsx_netmask_0.Value = $esxiSubnetMask
$nsxEdgeOvfConfig.Common.nsx_gateway_0.Value = $esxiGateway
$nsxEdgeOvfConfig.Common.nsx_dns1_0.Value = $dnsServers
$nsxEdgeOvfConfig.Common.nsx_domain_0.Value = $domain
$nsxEdgeOvfConfig.Common.nsx_ntp_0.Value = $ntpServers

$nsxEdgeOvfConfig.Common.mpUser.Value = "admin"
$nsxEdgeOvfConfig.Common.mpPassword.Value = $nsxMgmtPassword
$nsxEdgeOvfConfig.Common.mpIp.Value = $NSXTMgrIPAddress
$nsxEdgeOvfConfig.Common.mpThumbprint.Value = $nsxMgrCertThumbprint

$nsxEdgeOvfConfig.Common.nsx_isSSHEnabled.Value = $true
$nsxEdgeOvfConfig.Common.nsx_allowSSHRootLogin.Value = $true

$nsxEdgeOvfConfig.Common.nsx_passwd_0.Value = $nsxMgmtPassword
$nsxEdgeOvfConfig.Common.nsx_cli_username.Value = "admin"
$nsxEdgeOvfConfig.Common.nsx_cli_passwd_0.Value = $nsxMgmtPassword
$nsxEdgeOvfConfig.Common.nsx_cli_audit_username.Value = "audit"
$nsxEdgeOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $nsxMgmtPassword

Write-Host "Deploying NSX Edge VM $vmname ..."
$nsxedge_vm = Import-VApp -Source $ovaPath -OvfConfiguration $nsxEdgeOvfConfig -Name $vmname -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

Write-Host "Updating vCPU Count to $NSXTEdgevCPU & vMEM to $NSXTEdgevMEM GB ..."
Set-VM -Server $viConnection -VM $nsxedge_vm -NumCpu $NSXTEdgevCPU -MemoryGB $NSXTEdgevMEM -Confirm:$false 

Write-Host "Powering On $vmname ..."
$nsxedge_vm | Start-Vm -RunAsync | 

Write-Host "Moving Nested Edge into $VAppName vApp ..."
$VApp = Get-VApp -Name $VAppName -Server $viConnection -Location $cluster
$vcsaVM = Get-VM -Name $NSXTMgrDisplayName -Server $viConnection
Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
# Create new DVS for Edge routing

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false


## New code 

# Add edge as transport node
# https://developer.vmware.com/apis/1163/nsx-t
# Required variables
# transport_zone_id
# https://192.168.1.215/policy/api/v1/search?query=resource_type:(TransportZone) AND display_name:nsx-vlan-transportzone
# transport_zone_profile_ids (array)
# from transport_zone_id query. 
# "transport_zone_profile_ids": [
#     {
#         "profile_id": "52035bb3-ab02-4a08-9884-18631312e50a",
#         "resource_type": "BfdHealthMonitoringProfile"
#     }
# ],
# data_network_ids
# storage_id
# compute_id
# vc_id 

# post payload template
$body=@{
    "resource_type"="TransportNode"
    "display_name"=$EdgeDisplayName
    "description"="Edge Node"
    "node_deployment_info"=@{
        "display_name"=$EdgeDisplayName
        "resource_type"="EdgeNode"
        "ip_addresses"=@(
            "192.168.1.216"
            )
        "deployment_type"="VIRTUAL_MACHINE"
        "deployment_config"=@{
            "form_factor"="SMALL"
            "vm_deployment_config"=@{
                "placement_type"="BfdHealthMonitoringProfile"
                "vc_id"="dummyValue"
                "compute_id"="dummyValue"
                "storage_id"="dummyValue"
                "data_network_ids"=@(
                    "dummyValue"
                )
                "management_network_id"="dummyValue"
                "management_port_subnets"=@(@{
                    "ip_addresses"=@(
                        $edgeIpAddress
                    )
                    "prefix_length"="dummyValue"
                })
                "default_gateway_addresses"=@(
                    $esxiGateway
                )
                "reservation_info"=@{
                    "memory_reservation"=@{
                        "reservation_percentage"="0"
                    }
                    "cpu_reservation"=@{
                        "cpu_count"="0"
                        "memory_allocation_in_mb"="0"
                    }
                }
                "node_user_settings"=@{
                    "cli_password"="dummyValue"
                    "root_password"="dummyValue"
                    "cli_username"="admin"
                    "audit_username"="audit"
                    "audit_password"="dummyValue"
                }                
            }
            "node_settings"=@{
                "hostname"=$EdgeDisplayName
                "search_domains"=@(
                    "dummyValue"
                )
                "ntp_servers"=@(
                    "0.north-america.pool.ntp.org"
                    "1.north-america.pool.ntp.org"
                )
                "dns_server"=@(
                    $dnsServers
                )
                "enable_ssh"=$true
                "allow_ssh_root_login"=$true
            }
        }
    }
    "host_switches"=@(@{
        "host_switch_mode"="STANDARD"
        "host_switch_type"="NVDS"
        "host_switch_profile_ids"=@(@{
            "value"="dummyValue"
            "key"="UplinkHostSwitchProfile"
        })
        "host_switch_name"="nsxHostSwitch"
        "pnics"=@(@{
            "device_name"="fp-eth0"
            "uplink_name"="uplink-1"
        })
        "transport_zone_endpoints"=@(@{
            "transport_zone_id"="dummyValue"
            "transport_zone_profile_ids"=@(@{
                "profile_id"="dummyValue"
                "resource_type"="BfdHealthMonitoringProfile"
            })
        })
    })


}

# Create edge cluster

# Add edge to cluster



