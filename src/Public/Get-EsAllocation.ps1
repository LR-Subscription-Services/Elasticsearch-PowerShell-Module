<#
    Get-EsAllocation | Sort-Object -Property Node | Format-Table
    shards disk.indices disk.used disk.avail disk.total disk.percent host          ip            node
    ------ ------------ --------- ---------- ---------- ------------ ----          --            ----
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.79  10.23.156.79  USDFW21LR01v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.80  10.23.156.80  USDFW21LR02v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.81  10.23.156.81  USDFW21LR03v
    0      0b           67.2tb    40.3tb     107.5tb    62           10.23.156.82  10.23.156.82  USDFW21LR04v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.83  10.23.156.83  USDFW21LR05v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.84  10.23.156.84  USDFW21LR06v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.85  10.23.156.85  USDFW21LR07v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.86  10.23.156.86  USDFW21LR08v
    0      0b           67.2tb    40.2tb     107.5tb    62           10.23.156.87  10.23.156.87  USDFW21LR09v
    0      0b           67.3tb    40.2tb     107.5tb    62           10.23.156.134 10.23.156.134 USDFW21LR11v
    36     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.224  10.23.44.224  USDFW21LR20
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.224  10.23.44.224  USDFW21LR20-data
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.226  10.23.44.226  USDFW21LR21
    36     9.9tb        23.6tb    11.7tb     35.3tb     66           10.23.44.226  10.23.44.226  USDFW21LR21-data
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.210  10.23.44.210  USDFW21LR22
    36     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.210  10.23.44.210  USDFW21LR22-data
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.212  10.23.44.212  USDFW21LR23
    36     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.212  10.23.44.212  USDFW21LR23-data
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.238  10.23.44.238  USDFW21LR24
    36     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.238  10.23.44.238  USDFW21LR24-data
    36     9.8tb        25tb      10.2tb     35.3tb     70           10.23.44.239  10.23.44.239  USDFW21LR25
    37     9.8tb        25tb      10.2tb     35.3tb     70           10.23.44.239  10.23.44.239  USDFW21LR25-data
    36     9.9tb        23.6tb    11.6tb     35.3tb     66           10.23.44.134  10.23.44.134  USDFW21LR26
    37     9.8tb        23.6tb    11.6tb     35.3tb     66           10.23.44.134  10.23.44.134  USDFW21LR26-data
    36     9.9tb        23.6tb    11.6tb     35.3tb     66           10.23.44.150  10.23.44.150  USDFW21LR27
    36     9.9tb        23.6tb    11.6tb     35.3tb     66           10.23.44.150  10.23.44.150  USDFW21LR27-data
    36     9.8tb        23.8tb    11.5tb     35.3tb     67           10.23.44.176  10.23.44.176  USDFW21LR28
    37     9.8tb        23.8tb    11.5tb     35.3tb     67           10.23.44.176  10.23.44.176  USDFW21LR28-data
    37     9.9tb        23.6tb    11.7tb     35.3tb     66           10.23.44.190  10.23.44.190  USDFW21LR29
    37     9.8tb        23.6tb    11.7tb     35.3tb     66           10.23.44.190  10.23.44.190  USDFW21LR29-data
#>
Function Get-EsAllocation {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Node
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
            $RequestUrl = $BaseUrl + "/_cat/allocation/" + $Node + "?format=json"
        } else {
            $RequestUrl = $BaseUrl + "/_cluster/allocation/explain?format=json"
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