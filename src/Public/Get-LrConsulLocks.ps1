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
Function Get-LrConsulLocks {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Path = '/usr/local/logrhythm/tools/consul_locks.sh'
    )
    Begin {
    }
    
    Process {
        $lr_consulresults = $(sudo bash $Path)
        $ConsulLocks = [List[object]]::new()
        ForEach ($lr_consulresult in $lr_consulresults) {
            $lr_consulsplit = $lr_consulresult -split '\s+'
            $ConsulLocks.add([PSCustomObject]@{
                id = $lr_consulsplit[0]
                name = $lr_consulsplit[1]
                endpoint = $lr_consulsplit[2]
                hostname = $lr_consulsplit[2].split('_')[0]
                ipaddr = $lr_consulsplit[2].split('_')[1]
                guid = $lr_consulsplit[3]
            })
        }
        return $ConsulLocks
    }
}