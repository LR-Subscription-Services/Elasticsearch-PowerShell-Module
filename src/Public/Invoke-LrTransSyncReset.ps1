using namespace System
using namespace System.IO

Function Invoke-LrTransSyncReset {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Node
    )
    Begin {}

    Process {
        $PSSession = Test-LrClusterRemoteAccess -Hostnames $Node
        $IndexDelResults = Remove-EsIndex -Index 'field_translations' -Force
        $ServiceRestartResult = Invoke-Command -Session $PSSession -ScriptBlock {bash -c "sudo systemctl restart columbo"}
    }
}