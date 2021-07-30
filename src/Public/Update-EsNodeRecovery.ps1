using namespace System.Collections.Generic
Function Update-EsNodeRecovery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [int] $MaxBytesPerSec,


        [Parameter(Mandatory = $false, Position = 1)]
        [int] $ConcurrentRecoveries
    )
    Begin {
        $Headers = [Dictionary[string,string]]::new()
        $Headers.Add("Content-Type","application/json")

        $Master = Get-EsMaster

        if ($Master.ip) {
            $BaseUrl = "http://" + $Master.ip + ":9200"
        } else {
            $BaseUrl = "http://localhost:9200"
        }

        $Method = "Put"
    }
    
    Process {
        $RequestUrl = $BaseUrl + "/_cluster/settings?format=json"
        if ($null -eq $MaxBytesPerSec) {
            $_maxBytesPerSec = $null
        } else {
            $_maxBytesPerSec = $MaxBytesPerSec.ToString()+"mb"
        }
        $Body = [PSCustomObject]@{
            transient = [PSCustomObject]@{
                "indices.recovery.max_bytes_per_sec" = $_maxBytesPerSec
                "cluster.routing.allocation.node_concurrent_recoveries" = $ConcurrentRecoveries
                #"indices.recovery.concurrent_streams" = $ConcurrentStreams
            }
        } | ConvertTo-Json

        $Response = Invoke-RestMethod $RequestUrl -Method $Method -Body $Body -Headers $Headers

        return $Response
    }
}