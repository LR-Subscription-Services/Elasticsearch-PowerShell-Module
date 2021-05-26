<#
    get-esnodes

    ip           : 10.23.156.84
    heap.percent : 39
    ram.percent  : 99
    cpu          : 3
    load_1m      : 0.79
    load_5m      : 0.55
    load_15m     : 0.56
    node.role    : di
    master       : -
    name         : USDFW21LR06v

    ip           : 10.23.156.81
    heap.percent : 48
    ram.percent  : 98
    cpu          : 5
    load_1m      : 0.66
    load_5m      : 0.63
    load_15m     : 0.60
    node.role    : di
    master       : -
    name         : USDFW21LR03v


    AND - 
    Get-EsNodes | Sort-Object -Property 'name' | Format-Table
#>
Function Get-EsNodes {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [switch] $Stats
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
        if ($Stats) {
            $RequestUrl = $BaseUrl + "/_nodes/stats?format=json"
        } else {
            $RequestUrl = $BaseUrl + "/_cat/nodes?format=json"
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
        if ($Stats) {
            $NodeArray = [List[object]]::new()
            ForEach ($Node in $Response.nodes.PSObject.Properties) {
                
                $NodeDetails = [PSCustomObject]@{
                    id = $Node.name
                }
                ForEach ($Value in $Node.value) {
                    ForEach ($Property in $Value.PSObject.Properties) {
                        if ($Property.MemberType -like 'NoteProperty') {
                            $NodeDetails | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $Property.Value -Force
                        }
                    }
                }
                $NodeArray.add($NodeDetails)
            }
            $Results = [PSCustomObject]@{
                _nodes = $Response._nodes
                cluster_name = $Response.cluster_name
                nodes = $NodeArray
            }

            return $Results
        } else {
            return $Response
        }
    }
}