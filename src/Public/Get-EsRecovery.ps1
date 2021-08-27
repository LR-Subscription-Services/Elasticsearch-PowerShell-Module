<#
    Get-EsRecovery | more

    index                  : emdb_location_2021_03_31_12_40_17_31e717d8-4946-4624-9501-260145c7c3c6
    shard                  : 0
    time                   : 71ms
    type                   : empty_store
    stage                  : done
    source_host            : n/a
    source_node            : n/a
    target_host            : 10.23.44.210
    target_node            : USDFW21LR22-data
    repository             : n/a
    snapshot               : n/a
    files                  : 0
    files_recovered        : 0
    files_percent          : 0.0%
    files_total            : 0
    bytes                  : 0
    bytes_recovered        : 0
    bytes_percent          : 0.0%
    bytes_total            : 0
    translog_ops           : 0
    translog_ops_recovered : 0
    translog_ops_percent   : 100.0%

    AND
    index                                                                        shard time  type        stage source_host  source_node      target_host  target_node      repository
    -----                                                                        ----- ----  ----        ----- -----------  -----------      -----------  -----------      ----------
    emdb_location_2021_03_31_12_40_17_31e717d8-4946-4624-9501-260145c7c3c6       0     71ms  empty_store done  n/a          n/a              10.23.44.210 USDFW21LR22-data n/a
    emdb_location_2021_03_31_12_40_17_31e717d8-4946-4624-9501-260145c7c3c6       1     52ms  empty_store done  n/a          n/a              10.23.44.150 USDFW21LR27-data n/a
    logs-2021-03-20                                                              0     81ms  peer        done  10.23.44.210 USDFW21LR22-data 10.23.44.150 USDFW21LR27-data n/a
    logs-2021-03-20                                                              0     1.4h  peer        done  10.23.44.210 USDFW21LR22-data 10.23.44.238 USDFW21LR24      n/a
    logs-2021-03-20                                                              1     39ms  empty_store done  n/a          n/a              10.23.44.150 USDFW21LR27-data n/a
    logs-2021-03-20                                                              1     121ms peer        done  10.23.44.150 USDFW21LR27-data 10.23.44.224 USDFW21LR20      n/a
    logs-2021-03-20                                                              2     169ms empty_store done  n/a          n/a              10.23.44.224 USDFW21LR20      n/a
    logs-2021-03-20                                                              2     631ms peer        done  10.23.44.224 USDFW21LR20      10.23.44.176 USDFW21LR28      n/a
    logs-2021-03-20                                                              3     75ms  empty_store done  n/a          n/a              10.23.44.176 USDFW21LR28      n/a
    logs-2021-03-20                                                              3     662ms peer        done  10.23.44.176 USDFW21LR28      10.23.44.238 USDFW21LR24-data n/a
    logs-2021-03-20                                                              4     611ms peer        done  10.23.44.238 USDFW21LR24-data 10.23.44.134 USDFW21LR26      n/a
    logs-2021-03-20                                                              4     43ms  empty_store done  n/a          n/a              10.23.44.238 USDFW21LR24-data n/a
    logs-2021-03-20                                                              5     630ms peer        done  10.23.44.134 USDFW21LR26      10.23.44.150 USDFW21LR27      n/a
    logs-2021-03-20                                                              5     52ms  empty_store done  n/a          n/a              10.23.44.134 USDFW21LR26      n/a
    logs-2021-03-20                                                              6     44ms  peer        done  10.23.44.150 USDFW21LR27      10.23.44.239 USDFW21LR25      n/a
#>
Function Get-EsRecovery {
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
        if ($Index) {
            $RequestUrl = $BaseUrl + "/" + $Index +"/_recovery?human?format=json"
        } else {
            $RequestUrl = $BaseUrl + "/_cat/recovery?format=json"
        }

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