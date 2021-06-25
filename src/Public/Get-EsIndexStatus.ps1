Function Get-EsIndexStatus {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [bool] $DebugOutput
    )
    Begin {
        $Indexes_Bad = Get-EsIndex | Where-Object -Property status -ne "close" | Where-Object {$_.health -like 'yellow' -or $_.health -like 'red'} | Select-Object -ExpandProperty 'index'
        $Indexes_Good = Get-EsIndex | Where-Object -Property status -ne "close" | Where-Object {$_.health -like 'green'} | Select-Object -ExpandProperty 'index'
    }
    
    Process {
        $Shards_Unassigned = [List[object]]::new()
        ForEach ($BadIndex in $Indexes_Bad) {
            $PriShards_Unassigned = [List[object]]::new()
            $RepShards_Unassigned = [List[object]]::new()
            $ES_ShardStatus = Get-EsShards -Index $BadIndex -AdvanceHeaders | Where-Object -Property 'state' -like 'unassigned'
            ForEach ($ES_Shard in $ES_ShardStatus) {
                if ($ES_Shard.prirep -like "r") {
                    if ($RepShards_Unassigned -notcontains $ES_Shard) {
                        $RepShards_Unassigned.add($ES_Shard)
                    }
                }
                if ($ES_Shard.prirep -like "p") {
                    if ($RepShards_Unassigned -notcontains $ES_Shard) {
                        $PriShards_Unassigned.add($ES_Shard)
                    }
                }
            }
            $BadIndexInfo = [PSCustomObject]@{
                Index = $BadIndex
                Sum_BadPriShards = $PriShards_Unassigned.count 
                Sum_BadRepShards = $RepShards_Unassigned.count
                BadPriShards = $PriShards_Unassigned
                BadRepShards = $RepShards_Unassigned
            }
            if ($Shards_Unassigned -notcontains $BadIndexInfo) {
                $Shards_Unassigned.add($BadIndexInfo)
            }
            if ($DebugOutput -eq $true) {
                if ($BadIndexInfo.Sum_BadPriShards -gt 0) {
                    Write-Host "Index: $($BadIndexInfo.Index) | Status: Unassigned Primary Shards | Count: $($BadIndexInfo.Sum_BadPriShards)"
                    ForEach ($Reason in $($BadIndexInfo.BadPriShards | Where-Object -Property 'index' -like $BadIndexInfo.Index |Select-Object -Unique)) {
                        Write-Host "Index: $($BadIndexInfo.Index) | Reason: $($Reason.ur) | Note: $($Reason.un)"
                    }
                }
                if ($BadIndexInfo.Sum_BadRepShards -gt 0) {
                    Write-Host "Unassigned Replica Shards - Index: $($BadIndexInfo.Index) Count: $($BadIndexInfo.Sum_BadRepShards)"
                    ForEach ($Reason in $($BadIndexInfo.BadRepShards | Where-Object -Property 'index' -like $BadIndexInfo.Index |Select-Object -Unique)) {
                        Write-Host "Index: $($BadIndexInfo.Index) | Reason: $($Reason.ur) | Note: $($Reason.un)"
                    }
                }
            }
        }
        $Output = [PSCustomObject]@{
            good = $Indexes_Good
            bad = $Shards_Unassigned
        }
        return $Output
    }
}