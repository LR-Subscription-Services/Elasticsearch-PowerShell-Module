using namespace System
using namespace System.IO
using namespace System.Collections.Generic


# Maximum number of days back from the StartDate to inspect for indexes to migrate
$MaxDays = 2
$DateRange_Start = Get-Date "03/14/2021"
$DateRange_End = $DateRange_Start.AddDays(-$MaxDays)

#Invoke-RestMethod $RequestUrl -Headers $Headers -Method $Method -SkipCertificateCheck
$HotDiskThreshold=80
$WarmDiskThreshold=90
#HEAP size Threshold , it must be less than 80% 
$HEAPThreshold=75

# RequiredParamaters - Must be completed before executing
$ElasticSearch_NodeCount = 4
$Index_CloseTo = 1

$ColumboServer = $null 

# Amount of time to pause inbetween Stage inner Do {} While/Until loops.
$IterationDelay = 5

# Establish Cluster Nodes based on LogRhythm's Hosts file
$es_ClusterHosts = $(Get-LrClusterHosts -EsMaster)


$RestartOrder = [List[object]]::new()
# Warm Nodes
ForEach ($Node in $($es_ClusterHosts | Where-Object -Property type -like 'warm')) {
    $RestartOrder.Add($Node)
}
# Hot Nodes that are not Master
ForEach ($Node in $($es_ClusterHosts | Where-Object -Property type -like 'hot' | Where-Object -Property master -eq $false)) {
    $RestartOrder.Add($Node)
}
# Master Hot Node
ForEach ($Node in $($es_ClusterHosts | Where-Object -Property type -like 'hot' | Where-Object -Property master -eq $true)) {
    $RestartOrder.Add($Node)
}

# Master Last
# -- Master Data Node

$Stages = [List[object]]::new()
$Stages.add([PSCustomObject]@{
    Name = "Pre"
    ClusterStatus = "Green"
    ClusterHosts = $(Get-LrClusterHosts)
    SSH = "Verify"
    Routing = "All"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Start"
    ClusterStatus = "Green"
    SSH = $null
    Routing = "Primaries"  
    Flush = $true
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Running"
    ClusterStatus = "Yellow"
    SSH = $null
    Routing = "Primaries"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Completed"
    ClusterStatus = "Green"
    SSH = $null
    Routing = "All"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "End"
    ClusterStatus = "Green"
    SSH = "Verify"
    Routing = "All"
    Flush = $false
    ManualCheck = $true
})

# Status to support aborting at the transition point from the exit of one process tage prior to beginning the next stage
$AbortStatus = $false

# Variable to define TextCulture enabling the ability to updating string values ToTiltleCase syntax.
$TC = (Get-Culture).TextInfo

# Begin
ForEach ($Stage in $Stages) {
    # Retrieve Cluster Status at the start of each new Stage
    $es_ClusterHealth = Get-EsClusterHealth
    $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
    $lr_ConsulLocks = Get-LrConsulLocks
    # Check if the AbortStatus has been set to True.
    if ($AbortStatus -eq $true) {
        write-host "Status | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Abort Status | Abort Status set to $($AbortStatus).  Aborting Rolling Restart Automation."
        break
    }
    write-host "Status | Stage: $($Stage.Name) | Health: $es_ClusterStatus  | Rolling Restart | Begin Stage | Stage: $($Stage.Name)"
    
    # Status to support validating transition to the next stage
    $TransitionStage = $false
    if ($Stage.name -Like "Pre") {
        Do {
            # Begin with validating remote access into the DX cluster's nodes
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: SSH Verification | Begin Stage | Target: $($Stage.SSH)"
            $rs_SessionStatus = Test-LrClusterRemoteAccess -HostNames $es_ClusterHosts.ipaddr
            
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: SSH Verification | End Stage | Target: $($Stage.SSH)"

            # Next transition into validating ElasticSearch Cluster Status.  If the Status is not Healthy, validate basic settings that would prevent a Healthy status.
            # If the basic settings are not set to the pre-defined requirement, update the setting and monitor the environment for recovery.
            # If the recovery monitoring does not progress the process will ultimately abort, indicating the cause for the abort (total max retries or max retries without progress)
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Health Validation | Begin Stage | Target: $($Stage.ClusterStatus)"
            
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Health Validation | Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            # Cluster is Green, record Node details (ip, heap, ram, cpu, load, role, master, name)
            $es_Nodes = Get-EsNodes
            # Cluster is Green, record Cluster Node Count
            $es_ClusterNodesMax = $es_ClusterStatus.number_of_nodes
            # Cluster is Green, record the current Master node
            $es_Master = Get-EsMaster
            # Retrieve IndexStatus
            $es_PreIndexStatus = Get-EsIndexStatus
            # Retrieve a copy of the current Elasticsearch Settings
            $es_PreClusterSettings = Get-EsSettings 

            write-host "Warning | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Health Validation | Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            $IndexStatus = Get-EsIndexStatus
            $IndexSettings = Get-EsSettings 
            
            # If the current stage does not have the Shard allocation enabed, update the transient cluster routing to target to support cluster health recovery
            # This check inspects the current transient/temporary setting applied to the DX cluster
            if ($IndexSettings.transient.cluster.routing.allocation.enable -and $IndexSettings.transient.cluster.routing.allocation.enable -notlike $Stage.Routing) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Current: $($IndexSettings.transient.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
                $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                if ($tmp_VerifyAck.acknowledged) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Set Cluster routing settings to target: $($tmp_VerifyAck.transient)"
                } else {
                    write-host "Error | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Unable to update cluster settings to target: $($Stage.Routing)"
                }
            }

            # This check inspects the current persistent setting applied to the DX cluster for routing.
            if ($IndexSettings.persistent.cluster.routing.allocation.enable -and $IndexSettings.persistent.cluster.routing.allocation.enable -notlike $Stage.Routing) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Current: $($IndexSettings.persistent.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
                $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                if ($tmp_VerifyAck.acknowledged) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Set Cluster routing settings to target: $($tmp_VerifyAck.transient)"
                } else {
                    write-host "Error | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Unable to update cluster settings to target: $($Stage.Routing)"
                }
            }
    

            # Monitor Cluster Recovery
            if ($es_ClusterStatus -notlike "green") {
                # Instantiate variables associated with monitoring cluster recovery.
                $MaxInitConsecZero = 10
                $MaxNodeConsecNonMax = 50
                $RetryMax = 20
                $RetrySleep = 5
                $CurrentRetry = 0
                $PreviousUnAssigned = 0
                $CurrentUnassigned = 0
                $InitHistory = [List[int]]::new()
                Do {
                    start-sleep $RetrySleep
                    $es_ClusterHealth = Get-EsClusterHealth
                    $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))

                    if ($($es_ClusterStatus.number_of_nodes) -ne $ClusterNodesMax) {
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Nodes | Count: $($es_ClusterHealth.number_of_nodes) Target: $($ClusterNodesMax)  Attempt: $CurrentRetry  Remaining: $($RetryMax - $CurrentRetry)"
                        $RetryMax += 1
                    } else {
                        $CurrentRetry += 1
                        $InitHistory.Add($($es_ClusterHealth.initializing_shards))
        
                        $CurrentUnassigned = $($es_ClusterHealth.unassigned_shards)
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Unassigned Shards | Unassigned: $($es_ClusterHealth.unassigned_shards)  Initializing: $($es_ClusterHealth.initializing_shards)  Attempt: $CurrentRetry  Remaining: $($RetryMax - $CurrentRetry)"
        
                        $InitHistoryStats = $($InitHistory | Select-Object -Last 10 | Measure-Object -Maximum -Minimum -Sum -Average)
                    }
                } until (($CurrentRetry -ge $RetryMax) -or ($es_ClusterStatus -like "green") -or (($InitHistoryStats.count -eq $MaxInitConsecZero) -and ($InitHistoryStats.sum -eq 0)))
            }
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Health Validation | End | Target Requirement Met"

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Check Required: $($Stage.ManualCheck)"
            if ($Stage.ManualCheck -eq $true) {
                $Title    = "Elasticsearch Rolling Restart"
                $Question = 'Are you sure you want to proceed?'
                $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                $UserDecision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)
                if ($UserDecision -eq 0) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    Write-Host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }


            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)        
    }

    # Begin Section - Start
    if ($Stage.name -Like "Start") {
        Do {
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            $IndexStatus = Get-EsIndexStatus
            $IndexSettings = Get-EsSettings 
            
            # If the current stage does not have the Shard allocation enabed, update the transient cluster routing to target to support cluster health recovery
            # This check inspects the current transient/temporary setting applied to the DX cluster
            if ($IndexSettings.transient.cluster.routing.allocation.enable -and $IndexSettings.transient.cluster.routing.allocation.enable -notlike $Stage.Routing) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Current: $($IndexSettings.transient.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
                $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                if ($tmp_VerifyAck.acknowledged) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Set Cluster routing settings to target: $($tmp_VerifyAck.transient)"
                } else {
                    write-host "Error | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Unable to update cluster settings to target: $($Stage.Routing)"
                }
            }

            # This check inspects the current persistent setting applied to the DX cluster for routing.
            if ($IndexSettings.persistent.cluster.routing.allocation.enable -and $IndexSettings.persistent.cluster.routing.allocation.enable -notlike $Stage.Routing) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Current: $($IndexSettings.persistent.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
                $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                if ($tmp_VerifyAck.acknowledged) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Set Cluster routing settings to target: $($tmp_VerifyAck.transient)"
                } else {
                    write-host "Error | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Routing | Unable to update cluster settings to target: $($Stage.Routing)"
                }
            }

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Flush | Submitting cluster flush to Elasticsearch Master Node"
            $FlushResults = Invoke-EsFlushSync
            $FlushSuccessSum = $FlushResults | Measure-Object -Property 'successful' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushFailSum = $FlushResults | Measure-Object -Property 'failed' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushTotal = $FlushResults | Measure-Object -Property 'total' -Sum | Select-Object -ExpandProperty 'Sum'
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Flush | Total Shards: $FlushTotal  Sucessful: $FlushSuccessSum  Failed: $FlushFailSum"

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Check Required: $($Stage.ManualCheck)"
            if ($Stage.ManualCheck -eq $true) {
                $Title    = "Elasticsearch Rolling Restart"
                $Question = 'Are you sure you want to proceed?'
                $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                $UserDecision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)
                if ($UserDecision -eq 0) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    Write-Host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }

            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }

    # Begin Section - Start
    if ($Stage.name -Like "Running") {
        ForEach ($Node in $RestartOrder) {
            Do {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Restart Node | Node: $($Node.hostname) | Note here"

                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Node: $($Node.hostname) | Check Required: $($Stage.ManualCheck)"
                if ($Stage.ManualCheck -eq $true) {
                    $Title    = "Node Complete"
                    $Question = 'Do you want to proceed onto the next node?'
                    $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                    $UserDecision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)
                    if ($UserDecision -eq 0) {
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification |  Node: $($Node.hostname) | Manual authorization granted.  Proceeding to next stage."
                        $TransitionStage = $true
                    } else {
                        Write-Host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification |  Node: $($Node.hostname) | Aborting rolling restart process due to manual halt."
                        $AbortStatus = $true
                    }
                } else {
                    $TransitionStage -eq $true
                }
            } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
        }
    }
    
            # End Section - Start
    write-host "Status | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Rolling Restart | End Stage | Stage: $($Stage.Name)"
}




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
        $DesiredRoutingState = 'all'

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
