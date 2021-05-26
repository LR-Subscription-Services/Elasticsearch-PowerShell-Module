Function Update-EsIndexReplicas {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Index,


        [Parameter(Mandatory = $true, Position = 1)]
        [int] $Replicas
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
        $RequestUrl = $BaseUrl + "/" + $Index + "/_settings?format=json"

        $Body = [PSCustomObject]@{
            "index" = [PSCustomObject]@{
                number_of_replicas = $Replicas
            }
        } | ConvertTo-Json

        $Response = Invoke-RestMethod $RequestUrl -Method $Method -Body $Body -Headers $Headers

        return $Response
    }
}