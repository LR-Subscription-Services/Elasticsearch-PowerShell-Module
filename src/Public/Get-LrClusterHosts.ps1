using namespace System
using namespace System.IO
using namespace System.Collections.Generic
<#
    Get-LrConsulLocks
    id       : NsiCxBgr
    name     : bulldozer
    endpoint : LRDX1_172.17.5.101
    hostname : LRDX1
    ipaddr   : 172.17.5.101
    guid     : 076c06a9-33f6-bc3e-8571-987ba5692630

    id       : NsiCxBgr
    name     : gomaintain
    endpoint : LRDXW_172.17.5.104
    hostname : LRDXW
    ipaddr   : 172.17.5.104
    guid     : e80efd78-0c22-1efd-7b1f-c3860913fae4

    id       : NsiCxBgr
    name     : carpenter
    endpoint : LRDX2_172.17.5.102
    hostname : LRDX2
    ipaddr   : 172.17.5.102
    guid     : 126581ee-8708-7d1b-6ac4-78a56481a6f0

#>
Function Get-LrClusterHosts {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Path = '/home/logrhythm/Soft/hosts',

        [Parameter(Mandatory = $false, Position = 1)]
        [switch] $EsMaster
    )
    Begin {
    }
    
    Process {
        $lr_hostsresults = $(get-content -Path $Path)
        $LrHosts = [List[object]]::new()
        ForEach ($lr_hostsresult in $lr_hostsresults) {
            $lr_hostsplit = $lr_hostsresult -split '\s+'
            $LrHosts.add([PSCustomObject]@{
                ipaddr = $lr_hostsplit[0]
                hostname = $lr_hostsplit[1]
                type = $lr_hostsplit[2]
            })
        }

        if ($ESMaster) {
            $EsMasterResults = $(Get-EsMaster)
            ForEach ($LrHost in $LrHosts) {
                if ($LrHost.ipaddr -eq $EsMasterResults.ip) {
                    $LrHost | Add-Member -MemberType NoteProperty -Name 'master' -Value $true -Force
                } else {
                    $LrHost | Add-Member -MemberType NoteProperty -Name 'master' -Value $false -Force
                }
            }
        }
        return $LrHosts
    }
}