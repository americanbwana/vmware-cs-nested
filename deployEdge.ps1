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

$ovaPath = "/var/workspace_cache/repo/edge/nsx-edge-3.1.3.3.0.18684496.ovf"
#           /var/workspace_cache/repo/edge/nsx-edge-3.1.3.3.0.18684496.ovf
$EdgeDisplayName = "Nested-Edge-" + $BUILDTIME

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

# Disconnect viserver
Disconnect-VIServer -Server * -Force -Confirm:$false
