<#
    Get-EsMaster

    id                     host         ip           node
    --                     ----         --           ----
    5phx55XQTP25Fb60rJfG4w 10.23.44.239 10.23.44.239 USDFW21LR25
#>
Function Get-EsMaster {
    [CmdletBinding()]
    Param(
    )
    Begin {
        $Headers = [Dictionary[string,string]]::new()
        $Headers.Add("Content-Type","application/json")

        $BaseUrl = "http://localhost:9200"

        $Method = "Get"
    }
    
    Process {
        $RequestUrl = $BaseUrl + "/_cat/master?format=json"
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