using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Invoke-EsFlushSync {
    [CmdletBinding()]
    Param()
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

        $CuratedResults = [List[object]]::new()
    }

    Process {
        $RequestUrl = $BaseUrl + "/_flush/synced?format=json"
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

        $Response.PSObject.Properties | ForEach-Object {
            $CuratedResults.add([PSCustomObject]@{
                name = $_.Name
                total = $_.Value.total
                successful = $_.Value.successful
                failed = $_.Value.failed
            })
            
        }
        return $CuratedResults
    }
}