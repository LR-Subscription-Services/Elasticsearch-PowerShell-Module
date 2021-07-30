using namespace System.Collections.Generic
Function Update-EsNodeDelayTimeout {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [int] $Value,

        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Type = "m"
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
        $RequestUrl = $BaseUrl + "/_all/_settings?format=json"
        if ($null -eq $Value) {
            $_value = "5" + $Type
        } else {
            $_value = $Value.ToString()+$Type
        }
        $Body = [PSCustomObject]@{
            settings = [PSCustomObject]@{
                "index.unassigned.node_left.delayed_timeout" = $_value
            }
        } | ConvertTo-Json

        $Response = Invoke-RestMethod $RequestUrl -Method $Method -Body $Body -Headers $Headers

        return $Response
    }
}