# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope AllUsers

# connect using Env. 
Connect-VIserver -User $Env:vCenterUser -Password $Env:vCenterPass -Server $Env:vCenter 
