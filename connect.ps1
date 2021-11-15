# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope AllUsers

# print out ENV
Get-ChildItem Env:
# connect using Env. 
Connect-VIserver -User $Env:vCenterUser -Password $Env:vCenterPass -Server $Env:vCenter 

# Verify the connection by listing the datacenters
Get-Datacenter