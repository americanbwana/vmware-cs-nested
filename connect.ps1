# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope AllUsers

# print out ENV
$myEnv = Get-ChildItem Env:
write-host $myEnv
# connect using Env. 
$vcenter = Connect-VIserver -User $Env:vCenterUser -Password $Env:vCenterPass -Server $Env:vCenter -Verbose


# Verify the connection by listing the datacenters
$datacenter = Get-Datacenter -V 

Write-Host $datacenter