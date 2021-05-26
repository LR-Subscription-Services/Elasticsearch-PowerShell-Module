<#
    cluster_name                     : LRCLUSTER01
    status                           : green
    timed_out                        : False
    number_of_nodes                  : 30
    number_of_data_nodes             : 30
    active_primary_shards            : 370
    active_shards                    : 730
    relocating_shards                : 0
    initializing_shards              : 0
    unassigned_shards                : 0
    delayed_unassigned_shards        : 0
    number_of_pending_tasks          : 0
    number_of_in_flight_fetch        : 0
    task_max_waiting_in_queue_millis : 0
    active_shards_percent_as_number  : 100
#>
Function Get-EsClusterHealth {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Index
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

        $Method = "Get"
    }
    
    Process {
        $RequestUrl = $BaseUrl + "/_cluster/health?format=json"
        Try {
            $Response = Invoke-RestMethod $RequestUrl -Method $Method -Headers $Headers 
        } Catch {
            if ($_.ErrorDetails.Message) {
                $ErrorData = $_.ErrorDetails.Message | ConvertFrom-Json
                Return $ErrorData
            } else {
                return $_
            }
        }
        return $Response
    }
}