using namespace System
using namespace System.IO

Function Invoke-LrEmdbSyncReset {
    [CmdletBinding()]
    Param()
    Begin {
        
    }

    Process {
        $ConsulLocks = Get-LrConsulLocks
        $PSSession = Test-LrClusterRemoteAccess -Hostnames $($ConsulLocks | Where-Object -Property name -like 'carpenter' | Select-Object -ExpandProperty ipaddr)
        $IndexDelResults = Remove-EsIndex -Index 'emdb_*' -Force
        $ServiceRestartResult = Invoke-Command -Session $PSSession -ScriptBlock {bash -c "sudo systemctl restart carpenter"}
    }
}