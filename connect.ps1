# Disable SSL checking
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope AllUsers

# connect using Env. 
Connect-VIserver -User $Env:vCenter-User -Password $Env:vCenter-Pass -Server $Env:vCenter 
