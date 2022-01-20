# Author: Dana Gertsch - @knotacoder / https://knotacoder.com
# December 2021
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

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "admin",$nsxMgmtPassword)))

# $getProjectUri = "yourUri"
# Invoke-RestMethod -Method Get -Uri $getProjectUri -Headers @{Authorization = "Basic $base64AuthInfo" } -Credential $credential -ContentType "application/json"
Write-Host $nsxtMgmtIpAddress 
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/eula/accept"
Write-Host $updateURI
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST  -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "Accept EULA $result"

$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/telemetry/agreement"
Write-Host $updateURI

# $body = @{"telemetry_agreement_displayed"=$true;"_revision"=0;"resource_type"="TelemetryAgreement"} | ConvertTo-Json -Depth 5
$body=@{
    "telemetry_agreement_displayed"=$true
    "_revision"=0 
    "resource_type"="TelemetryAgreement"
} | ConvertTo-Json -Depth 5
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method PUT -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "Telemetry Agreement $result"

$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/license"
$body = @{
    "license_key"=$nsxtLicense
} | ConvertTo-Json -Depth 5
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method PUT -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "License application $result"

# Add VC
# need thumbprint
$VCURL = "https://" + $vcsaHostname + ":443"
$VCThumbprint = Get-SSLThumbprint256 -URL $VCURL
Write-Host $VCThumbprint
# POST https://<nsx-mgr>/api/v1/fabric/compute-managers
# build body
$credential = @{"credential_type"="UsernamePasswordLoginCredential";"username"="administrator@vsphere.local";"password"=$esxiPassword;"thumbprint"=$VCThumbprint}
$body = @{
    "server"=$vcsaHostname
    "origin_type"="vCenter"
    "credential"=$credential
    "description"="Default vCenter"
    "display_name"="vCenter" 
} | ConvertTo-Json -Depth 5
Write-Host $body
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/fabric/compute-managers"
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "Add Compute result $result"
$computeId=$result.id 

# IP Pool but with a useable result payload
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/pools/ip-pools"
$body=@{
    "display_name"="Ip Pool 01"
    "description"="First IP Pool"
    "subnets"=@(@{
        "dns_nameservers"=@($dnsServers)
        "allocation_ranges"=@(@{
            "start"=$poolStartIp
            "end"=$poolEndIp
        })
        "gateway_ip"=$esxiGateway
        "cidr"=$poolCidr
    })
} | ConvertTo-Json -Depth 5
Write-Host "New IP Pool body $body" 
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "New IP Pool result $result"
$ipPoolId=$result.id

# $body=@{"display_name"="Default IP Pool";"description"="Default IP Pool"} | ConvertTo-Json -Depth 5 
# $result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method PATCH -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
# # Returns 201 
# POST https://<nsx-mgr>/api/v1/pools/ip-pools
# {
#   "display_name": "IPPool-IPV6-1",
#   "description": "IPPool-IPV6-1 Description",
#   "subnets": [
#     {
#         "dns_nameservers": ["2002:a70:cbfa:1:1:1:1:1"],
#         "allocation_ranges": [
#             {
#                 "start": "2002:a70:cbfa:0:0:0:0:1",
#                 "end": "2002:a70:cbfa:0:0:0:0:5"
#             }
#         ],
#        "gateway_ip": "2002:a80:cbfa:0:0:0:0:255",
#        "cidr": "2002:a70:cbfa:0:0:0:0:0/124"
#     }
#   ]
# }


# # IP Pool
# $updateURI = "https://" + $nsxtMgmtIpAddress + "/policy/api/v1/infra/ip-pools/IpPool1"
# $body=@{"display_name"="Default IP Pool";"description"="Default IP Pool"} | ConvertTo-Json -Depth 5 
# $result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method PATCH -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
# # Returns 201 

# # Add Subnet Range
# $updateURI = "https://" + $nsxtMgmtIpAddress + "/policy/api/v1/infra/ip-pools/IpPool1/ip-subnets/Subnet1"
# $allocationRange=@(@{"start"="192.168.1.240";"end"="192.168.1.254"})
# $body=@{"cidr"="192.168.1.0/24";"gateway_ip"="192.168.1.1";"dns_nameservers"=@("192.168.1.200");"dns_suffix"="corp.local";"resource_type"="IpAddressPoolStaticSubnet";"allocation_ranges"=$allocationRange;"description"="Default Range";"display_name"="Default Range"} | ConvertTo-Json -Depth 5 
# Write-Host $body
# $result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method PUT -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
# Write-Host $result
# $subnetRangeId=$result.id 

# Create Transport Zone
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/transport-zones"
$body=@{"display_name"="tz1";"host_switch_name"="/api/v1/transport-zones";"description"="Transport Zone 1";"transport_type"="OVERLAY"} | ConvertTo-Json -Depth 5 
Write-Host "TZ body "
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "Create TZ result - $result"
$transportZoneId=$result.id 
$hostSwitchId=$result.host_switch_id 

# Create Uplink Profile
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/host-switch-profiles"
# $teaming=@(@{"standby_list"=@();"active_list"=@(@{"uplink_name"="uplink3";"uplink_type"="PNIC"};"policy"="FAILOVER_ORDER")})
$teaming=@{"standby_list"=@();"active_list"=@(@{"uplink_name"="uplink3";"uplink_type"="PNIC"});"policy"="FAILOVER_ORDER"}
Write-Host "teaming body $teaming"
$body =@{"resource_type"="UplinkHostSwitchProfile";"display_name"="uplinkProfile2";"teaming"=$teaming;"transport_vlan"=0} | ConvertTo-Json -Depth 5 
Write-Host "Create Uplink Profile body - $body"
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body $body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Write-Host "Create TZ result - $result"
$hostSwitchProfileId=$result.id

# Create Transport Node Profile
# Need to wait until the initial inventory is complete.  Otherwise the host_switch_id is null 
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/fabric/virtual-switches"
# start the loop
Do {
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method GET  -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
# $host_switch_id=$result.results[0] | ConvertFrom-Json
Start-Sleep -s 15
Write-Host "Waiting for Fabric Discovery to complete"
} Until ($result.result_count -gt 0)
# end the loop 
$host_switch_id=$result.results.uuid
Write-Host "host_switch_id " $host_switch_id


# Default DVSwitch is DVSwtich
# POST https://<nsx-mgr>/api/v1/transport-node-profiles
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/transport-node-profiles"
$body=@{
    "resource_type"="TransportNodeProfile"
    "display_name"="Transport Node Profile Demo"
    "description"="Transport Node Profile to be applied to a cluster"
    "host_switch_spec"=@{
        "resource_type"="StandardHostSwitchSpec"
        "host_switches"=@(@{"host_switch_profile_ids"=@(@{
            "value"=$hostSwitchProfileId
            "key"="UplinkHostSwitchProfile"
        })
            "host_switch_mode"="STANDARD"
            "host_switch_id"=$host_switch_id
            "host_switch_type"="VDS"
            "host_switch_name"="DVSwitch"
            "uplinks"=@(@{
                "vds_uplink_name"="uplink1"
                "uplink_name"="uplink3"
            })
            "ip_assignment_spec"=@{
                "resource_type"="StaticIpPoolSpec"
                "ip_pool_id"=$ipPoolId

            }
        "transport_zone_endpoints"=@(@{
            "transport_zone_id"=$transportZoneId
            })
        })
    }
}
Write-host ( $body | ConvertTo-Json -Depth 5 )
$result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body ($body | ConvertTo-Json -Depth 5 ) -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }

# GET Discovered nodes
# /api/v1/fabric/discovered-nodes
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/fabric/discovered-nodes"
# Make sure the nodes are discovered
Do {
$discovered_nodes = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method GET -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }
Start-Sleep -s 30 
Write-Host "Waiting for discovered node inventory."
} Until ($discovered_nodes.result_count -eq 3)
# End inventory check 

Write-Host "Nodes $discovered_nodes " 

foreach( $node in $discovered_nodes.results) {
# Loop through results and add each node by external_id
# /api/v1/fabric/discovered-nodes/<node-ext-id>?action=create_transport_node
    $updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/fabric/discovered-nodes/" + $node.external_id + "?action=create_transport_node"
    Write-Host "TN URL $updateURI"
    $body=@{
        "resource_type"="TransportNode"
        "description"="Transport Node"
        "display_name"=$node.display_name
        "host_switch_spec"=@{
            "resource_type"="StandardHostSwitchSpec"
            "host_switches"=@(@{
                "host_switch_profile_ids"=@(@{
                    "value"=$hostSwitchProfileId
                    "key"="UplinkHostSwitchProfile"
                })
                "host_switch_name"="DVSwitch"
                "uplinks"=@(@{
                    "uplink_name"="uplink3"
                    "vds_uplink_name"="uplink1"
                })
                "pnics"=@()
                "host_switch_id"=$host_switch_id
                "transport_zone_endpoints"=@(@{
                    "transport_zone_id"=$transportZoneId
                })
                "host_switch_mode"="STANDARD"
                "host_switch_type"="VDS"
                "ip_assignment_spec"=@{
                    "ip_pool_id"=$ipPoolId
                    "resource_type"="StaticIpPoolSpec"
                }
            })
        }
    } 
    Write-host ( $body | ConvertTo-Json -Depth 5  )
    $result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method POST -Body ($body | ConvertTo-Json -Depth 5 ) -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }

}
# Check the TN's until it is prepped for NSX. 
# "/api/v1/transport-nodes/state?status=SUCCESS"
$updateURI = "https://" + $nsxtMgmtIpAddress + "/api/v1/transport-nodes/state?status=SUCCESS"
Write-Host "Checking on TN preperation"
Do {
    Start-Sleep -Seconds 120
    Write-Host "Polling for SUCCESS state."
    $result = Invoke-RestMethod -uri $updateURI -SkipCertificateCheck -Method GET -Body -ContentType "application/json" -Headers @{Authorization = "Basic $base64AuthInfo" }

} Until ($result.result_count -eq 3)
# clean up

