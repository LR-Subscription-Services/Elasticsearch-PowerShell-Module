<#
    Get-EsIndexSettings -Index logs-2021-03-26
    --
    refresh_interval   : 30s
    indexing           : @{slowlog=}
    provided_name      : logs-2021-03-26
    creation_date      : 1616716739351
    unassigned         : @{node_left=}
    analysis           : @{filter=; analyzer=}
    number_of_replicas : 1
    uuid               : 7mUp7AujSkGBt8mzSBFLcA
    version            : @{created=5060699}
    codec              : best_compression
    routing            : @{allocation=}
    search             : @{slowlog=}
    number_of_shards   : 20
    merge              : @{scheduler=; policy=}
#>
Function Get-EsIndexSettings {
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
        $RequestUrl = $BaseUrl + "/" + $Index + "/_settings?format=json"
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
        
        return $($Response | Select-Object -ExpandProperty $Index | Select-Object -ExpandProperty Settings | Select-Object -ExpandProperty Index)
    }
}