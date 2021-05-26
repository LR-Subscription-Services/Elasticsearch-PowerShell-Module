<#
    get-essummary

    name         : USDFW21LR20
    cluster_name : LRCLUSTER01
    cluster_uuid : idorWID0T1aT73IYQJM7YQ
    version      : @{number=5.6.6; build_hash=7d99d36; build_date=1/9/2018 11:55:47 PM; build_snapshot=False; lucene_version=6.6.1}
    tagline      : You Know, for Search
#>
Function Get-EsSummary {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 1)]
        [string] $Master
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
        $RequestUrl = $BaseUrl + "/?format=json"
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