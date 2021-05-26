<#
    Get-EsShards -Index logs-2021-03-26

    index  : logs-2021-03-26
    shard  : 11
    prirep : p
    state  : STARTED
    docs   : 466930416
    store  : 324.3gb
    ip     : 10.23.44.134
    node   : USDFW21LR26-data

    index  : logs-2021-03-26
    shard  : 11
    prirep : r
    state  : STARTED
    docs   : 466930416
    store  : 325.1gb
    ip     : 10.23.44.190
    node   : USDFW21LR29
#>
Function Get-EsShards {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string] $Index,

        [Parameter(Mandatory = $false, Position = 1)]
        [switch] $AdvanceHeaders
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

        $Unassigned_Reasons = [PSCustomObject]@{
            ALLOCATION_FAILED = "Unassigned as a result of a failed allocation of the shard. "
            CLUSTER_RECOVERED = "Unassigned as a result of a full cluster recovery. "
            DANGLING_INDEX_IMPORTED = "Unassigned as a result of importing a dangling index. "
            EXISTING_INDEX_RESTORED = "Unassigned as a result of restoring into a closed index. "
            INDEX_CREATED = "Unassigned as a result of an API creation of an index. "
            INDEX_REOPENED = "Unassigned as a result of opening a closed index. "
            NEW_INDEX_RESTORED = "Unassigned as a result of restoring into a new index. "
            NODE_LEFT = "Unassigned as a result of the node hosting it leaving the cluster. "
            REALLOCATED_REPLICA = "A better replica location is identified and causes the existing replica allocation to be cancelled."
            REINITIALIZED = "When a shard moves from started back to initializing. "
            REPLICA_ADDED = "Unassigned as a result of explicit addition of a replica."
            REROUTE_CANCELLED = "Unassigned as a result of explicit cancel reroute command."
        }

        $Method = "Get"
    }
    
    Process {
        if ($AdvanceHeaders) {
            $HeaderContent = "?h=index,shard,prirep,state,docs,store,ip,node,ua,ud,uf,ur,&format=json"
        } else {
            $HeaderContent = "?format=json"
        }

        if ($Index) {
            $RequestUrl = $BaseUrl + "/_cat/shards/" + $Index + $HeaderContent 
        } else {
            $RequestUrl = $BaseUrl + "/_cat/shards" + $HeaderContent 
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

        ForEach($Entry in $Response) {
            if ($Entry.ur) {
                $Entry | Add-Member -MemberType NoteProperty -Name 'un' -Value $Unassigned_Reasons.$($Entry.ur) -Force
            }
        }

        return $Response
    }
}