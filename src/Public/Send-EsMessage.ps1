using namespace System.Collections.Generic
Function Send-EsMessage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Index,

        [Parameter(Mandatory = $true, Position = 1)]
        [object] $Body,


        [Parameter(Mandatory = $false, Position = 2)]
        [switch] $PassThru
    )
    Begin {
        $Headers = [Dictionary[string,string]]::new()
        $Headers.Add("Content-Type","application/json")

        $Method = "Post"

        $BaseUrl = "http://localhost:9200"
    }

    Process {
       
        $Body = $Body | ConvertTo-Json -Depth 4
        write-verbose "JSON Body:`n$Body"

        $RequestUrl = $BaseUrl + "/$Index/message"
        Try {
            $Response = Invoke-RestMethod $RequestUrl -Method $Method -Headers $Headers -Body $Body
        } Catch {
            if ($_.ErrorDetails.Message) {
                $ErrorData = $_.ErrorDetails.Message | ConvertFrom-Json
                Return $ErrorData
            } else {
                return $_
            }
        }

        if ($PassThru) {
            return $Response
        }
    }
}