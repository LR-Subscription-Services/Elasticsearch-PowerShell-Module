
# Good command: Get-EsIndex | Where-Object -Property status -like "open" | Sort-Object -Property index | Format-table

For ($i = $DateRange_Start; $i -gt $DateRange_End; $i = $i.AddDays(-1)) {
    $ElasticDateString = "logs-$($i.ToString("yyyy-MM-dd"))"
    Write-Host "Processing for index: $ElasticDateString"
    $IndexStatus = Get-EsIndex -Index $ElasticDateString
    if ($IndexStatus) {
        $SummaryNote = "Index: $ElasticDateString Status: $($IndexStatus.status) UUID: $($IndexStatus.uuid)"
        if ($IndexStatus.status -like "close") {
            Write-Host $SummaryNote
        } else {
            $IndexSettings = Get-EsIndexSettings -Index $ElasticDateString
            $SummaryNote = $SummaryNote + " Health: $($IndexStatus.health)  Index Type: $($IndexSettings.routing.allocation.require.box_type)"
            Write-Host $SummaryNote
            Write-Host "Primary Shards: $($IndexStatus.pri) Replica Shards: $($IndexStatus.rep) Doc Count: $($IndexStatus.'docs.count') Store Size: $($IndexStatus.'store.size')"
            if ($IndexSettings.routing.allocation.require.box_type -like "hot") {
                Write-Host "Identified Hot Node data within Date Range for migration to Warm Node."
                Write-Host "Update Node Box Type from type Hot to type Warm."
                if ($IndexSettings.number_of_replicas -ge 1) {
                    Write-Host "Number of Index Replicas: $($IndexSettings.number_of_replicas)"
                    Write-Host "Setting Index Replicas to: 0"
                    $ReplicaResults = Update-EsIndexReplicas -Index $ElasticDateString -Replicas 0
                    if ($ReplicaResults.acknowledged -eq $true) {
                        Write-Host "Successfully updated number of replicas to 0."
                    } else {
                        return "Update Replicas not accomplished."
                        
                        # Something wrong with replica change
                    }
                }
                
                $TypeResults = Update-EsIndexBoxType -Index $ElasticDateString -Type "warm"
                if ($TypeResults.acknowledged -eq $true) {
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
                } else {
                    return "Update box type not accomplished."
                }

                $IndexCloseStatus = Close-EsIndex -Index $ElasticDateString
                if (($IndexCloseStatus.acknowledge -eq $true) -or ($IndexCloseStatus.acknowledge -like "true")) {
                    Write-Host "Set Index to close status accomplished."
                } else {
                    return "Issue with setting Index to close status."
                }
            }
        }
    } else {
        return "Unable to retrieve any details for index: $ElasticDateString"
    }
}