<#
    Get-EsIndex
    ---
    health         :
    status         : close
    index          : logs-2020-11-17
    uuid           : fQownWIzQ2aq4fmDpP1atA
    pri            :
    rep            :
    docs.count     :
    docs.deleted   :
    store.size     :
    pri.store.size :

    health         :
    status         : close
    index          : logs-2021-02-05
    uuid           : -M8Usez4QKqBQEO8lQDFbQ
    pri            :
    rep            :
    docs.count     :
    docs.deleted   :
    store.size     :
    pri.store.size :

    health         : green
    status         : open
    index          : logs-2021-03-19
    uuid           : Scw4P0tVSdm3WHpdnwJ7-Q
    pri            : 20
    rep            : 1
    docs.count     : 7275698238
    docs.deleted   : 1969
    store.size     : 10.3tb
    pri.store.size : 5.1tb

    health         :
    status         : close
    index          : logs-2021-01-26
    uuid           : wAdokqycQF2mclC8xGKJww
    pri            :
    rep            :
    docs.count     :
    docs.deleted   :
    store.size     :
    pri.store.size :


    AND 
    Get-EsIndex -Index  logs-2021-03-19

    health         : green
    status         : open
    index          : logs-2021-03-19
    uuid           : Scw4P0tVSdm3WHpdnwJ7-Q
    pri            : 20
    rep            : 1
    docs.count     : 7275698238
    docs.deleted   : 1969
    store.size     : 10.3tb
    pri.store.size : 5.1tb



    AND
    Get-EsIndex -Index  logs-2021-01-26

    health         :
    status         : close
    index          : logs-2021-01-26
    uuid           : wAdokqycQF2mclC8xGKJww
    pri            :
    rep            :
    docs.count     :
    docs.deleted   :
    store.size     :
    pri.store.size :
#>
Function Get-EsIndex {
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
        $RequestUrl = $BaseUrl + "/_cat/indices/" + $Index + "?format=json"
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