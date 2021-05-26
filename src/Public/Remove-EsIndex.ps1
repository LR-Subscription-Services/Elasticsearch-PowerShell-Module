Function Remove-EsIndex {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Index,


        [Parameter(Mandatory = $false, Position = 2)]
        [switch] $Force
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
        

        $Method = "Delete"

        # Prompt for input
        $Title    = "Delete Elasticsearch Index - $Index"
        $Question = 'Are you sure you want to proceed?'
        $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    }
    
    Process {
        $RequestUrl = $BaseUrl + "/" + $Index + "?format=json"

        if ($Force) {
            $Response = Invoke-RestMethod $RequestUrl -Method $Method -Headers $Headers
        } else {
            $UserDecision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)
            if ($UserDecision -eq 0) {
                $Response = Invoke-RestMethod $RequestUrl -Method $Method -Headers $Headers
            } else {
                $Response = 'Index Delete Aborted'
            }
        }
        return $Response
    }
}