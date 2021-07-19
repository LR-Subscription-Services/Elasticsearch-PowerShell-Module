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
    }

    Process {
        $CuratedResults = [List[object]]::new()
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
            $Entry = [PSCustomObject]@{
                name = $_.Name
                total = $_.Value.total
                successful = $_.Value.successful
                failed = $_.Value.failed
            }
            if ($_.failures) {
                $Entry | Add-Member -MemberType NoteProperty -Name "failures" -Value $_.failures -Force
            }
            $CuratedResults.add($Entry)
            
        }
        return $CuratedResults
    }
}