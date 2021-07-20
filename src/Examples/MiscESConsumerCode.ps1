


if ($es_ClusterStatus.status -like "green") {
    write-host "Status is green, we're green to begin!"
    $es_Nodes = Get-EsNodes
    $es_ClusterNodesMax = $es_ClusterStatus.number_of_nodes
    $es_Master = Get-EsMaster
} else {
    write-host "Status is not green, we're not in a position to perform a rolling restart."
    $MaxInitConsecZero = 10
    $MaxNodeConsecNonMax = 50
    $RetryMax = 20
    $RetrySleep = 5
    $CurrentRetry = 0
    $PreviousUnAssigned = 0
    $CurrentUnassigned = 0
    $InitHistory = [List[int]]::new()
    if ($($es_ClusterStatus.number_of_nodes) -ne $ClusterNodesMax) {
        write-host "Cluster Status: $es_ClusterStatus  Current Node Count: $($es_ClusterStatus.number_of_nodes)  Target Node Count: $($ClusterNodesMax)  Attempt: $CurrentRetry  Attempts Remaining: $($RetryMax - $CurrentRetry)  Sleeping for: $LoopSleepTimer_Medium"
        $RetryMax += 1
    } else {
        # Check and update cluster routing allocation as required.
        $ClusterSettings = Get-EsSettings
        # Check transient first
        if ($ClusterSettings) {
            if ($ClusterSettings.transient.cluster.routing.allocation) {
                write-host "Cluster Routing Allocation - Transient: $($ClusterSettings.transient.cluster.routing.allocation.enable)"
            } else {
                Write-Host "Cluster Routing Allocation - Persistent: $($ClusterSettings.persistent.cluster.routing.allocation.enable)"
            }
        } else {
            write-host "Unable to retrieve Elasticsearch Cluster Settings."
            Exit 1
        }

        $CurrentUnassigned = $($es_Clusterstatus.unassigned_shards)
        if ($CurrentUnassigned -ne $($ClusterStatusHistory | Select-Object -ExpandProperty unassigned_shards -Last 1)) {
            $RetryMax += 5
        }
        write-host "Cluster Status: $es_ClusterStatus  Unassigned Shards: $($es_Clusterstatus.unassigned_shards)  Initializing Shards: $($es_Clusterstatus.initializing_shards)  Attempt: $CurrentRetry  Attempts Remaining: $($RetryMax - $CurrentRetry)  Sleeping for: $LoopSleepTimer_Medium"
    }
}



$PriShards_Yellow_Sum = Get-EsIndex | Where-Object -Property status -ne 'close' | Where-Object -Property health -like 'yellow' | Select-Object -ExpandProperty 'pri' | Measure-Object -Sum | Select-Object -ExpandProperty 'Sum'
$PriShards_Unassigned = Get-EsShards | Where-Object -Property 'prirep' -Like 'p' | Where-Object -Property 'state' -like 'unassigned'
$RepShards_Yellow_Sum = Get-EsIndex | Where-Object -Property status -ne 'close' | Where-Object -Property health -like 'yellow' | Select-Object -ExpandProperty 'rep' | Measure-Object -Sum | Select-Object -ExpandProperty 'Sum'
$RepShards_Unassigned = Get-EsShards | Where-Object -Property 'prirep' -Like 'r' | Where-Object -Property 'state' -like 'unassigned'

$Indexes_Bad = Get-EsIndex | Where-Object -Property status -ne "close" | Where-Object {$_.health -like 'yellow' -or $_.health -like 'red'} | Select-Object -ExpandProperty 'index'
$Indexes_Good = Get-EsIndex | Where-Object -Property status -ne "close" | Where-Object {$_.health -like 'green'} | Select-Object -ExpandProperty 'index'
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


# Disable Shard Allocation
Update-EsIndexRouting -Enable "primaries"
# Validate IndexRouting has been updated to set value
Do {
    Start-Sleep 15
    $ESSettings = Get-EsSettings
} Until ($ESSettings.transient.cluster.routing.allocation.enable -eq "primaries")


$FlushResults = Invoke-EsFlushSync


systemctl stop elasticsearch.service
# Start - Simulated Reboot
start-sleep 90
systemctl start elasticsearch.service
# END - Simulated Reboot
DO {
    $NodeStatus = get-esnodes
    Start-Sleep 30
} While ($TCond = $Tcond2)
Update-EsIndexRouting -Enable "null"
$ShardMigrationStatus = "InProgress"
Do {
    $EsShardRecoveryResults = Get-EsRecovery
    if ($EsShardRecoveryResults) {
        $RecoveryDetails = $EsShardRecoveryResults | Where-Object -Property 'index' -like $ElasticDateString | Where-Object -property 'type' -notlike 'empty_store' | Select-Object -Property index,type,shard,time,source_host,source_node,target_host,target_node,files_percent,bytes_percent,translog_ops_percent | Sort-Object -Property files_percent,bytes_percent,translog_ops_percent 
        $FilesPercent = $RecoveryDetails | Select-Object -ExpandProperty 'files_percent' | ForEach-Object {$_.replace("%","")} | Measure-Object -Average | Select-Object -ExpandProperty Average
        $TranslogPercent = $RecoveryDetails | Select-Object -ExpandProperty 'translog_ops_percent' | ForEach-Object {$_.replace("%","")} | Measure-Object -Average | Select-Object -ExpandProperty Average
        $BytesPercent = $RecoveryDetails | Select-Object -ExpandProperty bytes_percent | ForEach-Object {$_.replace("%","")} | Measure-Object -Average | Select-Object -ExpandProperty Average
        if (($FilesPercent -eq '100') -and ($TranslogPercent -eq '100') -and ($BytesPercent -eq '100')) {
            $ShardMigrationStatus = "Complete"
            write-Host "Migration Status: Complete"
        } else {
            $ShardMigrationStatus = "Index: $ElasticDateString  Status: InProgress  Files_Percent: $FilesPercent   Translog_Percent: $TranslogPercent   Bytes_Percent: $BytesPercent"
        }
    } else {
        return "Issue with recovering data from Get-EsRecovery cmdlet."
    }

    Write-Host "Task: Shard Migration  $ShardMigrationStatus"
    Start-Sleep 5
} Until ($ShardMigrationStatus -eq "Complete")
