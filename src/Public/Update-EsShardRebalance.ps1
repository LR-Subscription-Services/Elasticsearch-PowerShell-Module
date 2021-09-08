Function Update-EsShardRebalance {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateSet("all","primaries", "none", "null", ignorecase=$true)]
        [string] $Enable = "all",

        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateSet("always","indices_primaries_active", "indices_all_active", "null", ignorecase=$true)]
        [string] $Allow_Rebalance = "indices_all_active",

        [Parameter(Mandatory = $false, Position = 1)]
        [switch] $Persistent
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

        $Method = "Put"
    }

    Process {
        if ($Persistent) {
            # Request Body
            $Body = [PSCustomObject]@{
                persistent = [PSCustomObject]@{
                    "cluster.routing.rebalance.enable" = $Enable
                    "cluster.routing.allocation.allow_rebalance" = $Allow_Rebalance
                }
            }
        } else {
            # Request Body
            $Body = [PSCustomObject]@{
                transient = [PSCustomObject]@{
                    "cluster.routing.rebalance.enable" = $Enable
                    "cluster.routing.allocation.allow_rebalance" = $Allow_Rebalance
                }
            }
        }
        
        $Body = $Body | ConvertTo-Json
        write-verbose "JSON Body:`n$Body"

        $RequestUrl = $BaseUrl + "/_cluster/settings"
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


        $OutObject = [PSCustomObject]@{
            acknowledged = $Response.acknowledged
            setting = "cluster.routing.allocation.enable"
            persistent = $null
            transient = $null
        }

        if ($Response.transient.cluster.routing.allocation.enable) {
            $OutObject.transient = $Response.transient.cluster.routing.allocation.enable
        }

        if ($Response.persistent.cluster.routing.allocation.enable) {
            $OutObject.persistent = $Response.persistent.cluster.routing.allocation.enable
        }
        
        return $($OutObject)
    }
}