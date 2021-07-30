Function Close-EsIndex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
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

        $Method = "Post"
    }
    
    Process {
        $RequestUrl = $BaseUrl + "/" + $Index + "/_close?format=json"

        $Response = Invoke-RestMethod $RequestUrl -Method $Method -Headers $Headers

        return $Response
    }
}