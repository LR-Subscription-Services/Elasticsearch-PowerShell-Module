<#
    Get-EsSegments | more

    index        : logs-2021-03-20
    shard        : 0
    prirep       : r
    ip           : 10.23.44.150
    segment      : _3ut
    generation   : 4997
    docs.count   : 14094389
    docs.deleted : 0
    size         : 9.9gb
    size.memory  : 10703895
    committed    : true
    searchable   : true
    version      : 6.6.1
    compound     : false

    index        : logs-2021-03-20
    shard        : 0
    prirep       : r
    ip           : 10.23.44.150
    segment      : _5q1
    generation   : 7417
    docs.count   : 7750995
    docs.deleted : 0
    size         : 5.8gb
    size.memory  : 6943738
    committed    : true
    searchable   : true
    version      : 6.6.1
    compound     : false

    index        : logs-2021-03-20
    shard        : 0
    prirep       : r
    ip           : 10.23.44.150
    segment      : _84l
    generation   : 10533
    docs.count   : 13690231
    docs.deleted : 0
    size         : 9.9gb
    size.memory  : 10674526
    committed    : true
    searchable   : true
    version      : 6.6.1
    compound     : false



    and - 
    Get-EsSegments | Sort-Object -Property index,size | Format-Table
#>
Function Get-EsSegments {
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
        if ($Node) {
            $RequestUrl = $BaseUrl + "/_cat/segments/$Index?format=json"
        } else {
            $RequestUrl = $BaseUrl + "/_cat/segments?format=json"
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