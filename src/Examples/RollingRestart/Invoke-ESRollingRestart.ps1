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

# List of index that are closed as part of auto rolling restart to be re-opened in the Completed stage
$ClosedHotIndexes = [List[object]]::new()

# Master Last
# -- Master Data Node

$Stages = [List[object]]::new()
$Stages.add([PSCustomObject]@{
    Name = "Pre"
    ClusterStatus = "Green"
    ClusterHosts = $(Get-LrClusterHosts)
    SSH = "Verify"
    IndexSize = -1
    Routing = "All"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Start"
    ClusterStatus = "Green"
    SSH = $null
    IndexSize = 3
    Routing = "Primaries"
    Flush = $true
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Running"
    ClusterStatus = "Yellow"
    SSH = $null
    IndexSize = 3
    Routing = "Primaries"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Completed"
    ClusterStatus = "Green"
    SSH = $null
    IndexSize = -1
    Routing = "All"
    Flush = $false
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "End"
    ClusterStatus = "Green"
    SSH = "Verify"
    IndexSize = -1
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
        New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Abort Status' -logMessage "Abort Status set to $($AbortStatus).  Aborting Rolling Restart Automation."
        #write-host "Status | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Abort Status | Abort Status set to $($AbortStatus).  Aborting Rolling Restart Automation."
        break
    }
    New-ProcessLog -logSev s -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Begin Stage' -logMessage "Stage: $($Stage.Name)"

    
    # Status to support validating transition to the next stage
    $TransitionStage = $false
    if ($Stage.name -Like "Pre") {
        Do {
            # Begin with validating remote access into the DX cluster's nodes
            New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "Target: $($Stage.SSH)"

            $rs_SessionStatus = Test-LrClusterRemoteAccess -HostNames $es_ClusterHosts.ipaddr
            ForEach ($rs_SessionStat in $rs_SessionStatus) {
                if ($rs_SessionStat.Id -eq -1) {
                    New-ProcessLog -logSev e -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "$($rs_SessionStat.Error)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                    
                    $RetryMax = 20
                    $RetrySleep = 5
                    $CurrentRetry = 0
                    Do {
                        start-sleep $RetrySleep
                        $rs_SessionStat = Test-LrClusterRemoteAccess -HostNames $rs_SessionStat.ComputerName
                        if ($rs_SessionStat.Id -eq -1) {
                            $CurrentRetry += 1
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "$($rs_SessionStat.Error)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                        } else {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "Session ID: $($rs_SessionStat.Id)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                        }
                    } until (($CurrentRetry -ge $RetryMax) -or ($rs_SessionStat.State -like "Opened"))
                } else {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "Session ID: $($rs_SessionStat.Id)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                }
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'SSH Verification' -logMessage "Target: $($Stage.SSH)"

            # Next transition into validating ElasticSearch Cluster Status.  If the Status is not Healthy, validate basic settings that would prevent a Healthy status.
            # If the basic settings are not set to the pre-defined requirement, update the setting and monitor the environment for recovery.
            # If the recovery monitoring does not progress the process will ultimately abort, indicating the cause for the abort (total max retries or max retries without progress)

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
            if ($es_ClusterHealth -notlike 'Green') {
                New-ProcessLog -logSev w -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Cluster Health Validation' -logMessage "Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            } else {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Cluster Health Validation' -logMessage "Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            }
            
            $IndexStatus = Get-EsIndexStatus
            $IndexSettings = Get-EsSettings 
            
            # If the current stage does not have the Shard allocation enabed, update the transient cluster routing to target to support cluster health recovery
            # This check inspects the current transient/temporary setting applied to the DX cluster
            if ($IndexSettings.transient.cluster.routing.allocation.enable -and $IndexSettings.transient.cluster.routing.allocation.enable -notlike $Stage.Routing) {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Cluster Routing' -logMessage "Current: $($IndexSettings.transient.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
                
                $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                if ($tmp_VerifyAck.acknowledged) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Cluster Routing' -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
                    
                } else {
                    New-ProcessLog -logSev e -logStage $($Stage.Name) -esHealth $es_ClusterStatus -logStep 'Cluster Routing' -logMessage "Unable to update cluster transient settings to target: $($Stage.Routing)"
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
                    $PreviousUnAssigned = $($es_ClusterHealth.unassigned_shards)
                    $es_ClusterHealth = Get-EsClusterHealth
                    $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))

                    if ($($es_ClusterStatus.number_of_nodes) -ne $ClusterNodesMax) {
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Unassigned Shards | Cluster Nodes | Count: $($es_ClusterHealth.number_of_nodes) Target: $($ClusterNodesMax)  Attempt: $CurrentRetry  Remaining: $($RetryMax - $CurrentRetry)"
                        $RetryMax += 5
                    } else {
                        $CurrentRetry += 1
                        $InitHistory.Add($($es_ClusterHealth.initializing_shards))
        
                        $CurrentUnassigned = $($es_ClusterHealth.unassigned_shards)
                        if ($CurrentUnassigned -ne $PreviousUnAssigned) {
                            $RetryMax += 2
                            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Unassigned Shards | Recovery Progression | Unassigned: $($es_ClusterHealth.unassigned_shards)  Initializing: $($es_ClusterHealth.initializing_shards)  Attempt: $CurrentRetry  Remaining: $($RetryMax - $CurrentRetry)"
                        } else {
                            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Unassigned Shards | Recovery Stalled | Unassigned: $($es_ClusterHealth.unassigned_shards)  Initializing: $($es_ClusterHealth.initializing_shards)  Attempt: $CurrentRetry  Remaining: $($RetryMax - $CurrentRetry)"
                        }
                        $InitHistoryStats = $($InitHistory | Select-Object -Last 10 | Measure-Object -Maximum -Minimum -Sum -Average)
                    }
                } until (($CurrentRetry -ge $RetryMax) -or ($es_ClusterStatus -like "green") -or (($InitHistoryStats.count -eq $MaxInitConsecZero) -and ($InitHistoryStats.sum -eq 0)))
            }
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Health Validation | End | Target Requirement Met"

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Check Required: $($Stage.ManualCheck)"
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Elasticsearch Rolling Restart" -Question "Are you sure you want to proceed?"
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
            $Indexes = Get-EsIndex

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

            # Optional - Close down number of cluster indexes to reduce node recovery time
            if ($Stage.IndexSize -gt 0) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Close Index | Begin closing indicies to reduce recovery time requirements"

                $HotIndexes = $Indexes | Where-Object -FilterScript {($_.index -match 'logs-\d+') -and ($_.status -like 'open') -and ($_.rep -gt 0)} | Sort-Object index
                $TargetClosedIndexes = $HotIndexes | Select-Object -First $($HotIndexes.count - $Stage.IndexSize)
                $HotIndexOpen = $HotIndexes.count
                $HotIndexClosed = $TargetClosedIndexes.count
                ForEach ($TargetIndex in $TargetClosedIndexes) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Close Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize) | Closing Index: $($TargetIndex.index)"
                    $CloseStatus = Close-EsIndex -Index $TargetIndex.Index
                    if ($CloseStatus.acknowledged) {
                        $HotIndexOpen -= 1
                        $HotIndexClosed += 1
                        $ClosedHotIndexes.add($TargetIndex)
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Close Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize) | Close Status: Completed"
                    } else {
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Close Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize) | Close Status: Incomplete"
                        write-host $CloseStatus
                    }
                    
                }
            }

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Flush | Submitting cluster flush to Elasticsearch Master Node"
            $FlushResults = Invoke-EsFlushSync
            <#
            $FlushSuccessSum = $FlushResults | Measure-Object -Property 'successful' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushFailSum = $FlushResults | Measure-Object -Property 'failed' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushTotal = $FlushResults | Measure-Object -Property 'total' -Sum | Select-Object -ExpandProperty 'Sum'
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Flush | Total Shards: $FlushTotal  Sucessful: $FlushSuccessSum  Failed: $FlushFailSum"
            #>
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Check Required: $($Stage.ManualCheck)"
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
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
                # Add in restart to system here, using $($Node.ipaddr)
                $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr)
                $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {get-host}
                Write-Host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Node: $($Node.hostname) | PSComputerName: $($HostResult.PSComputerName)   RunSpace: $($HostResult.Name)"
                
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Node: $($Node.hostname) | Check Required: $($Stage.ManualCheck)"
                if ($Stage.ManualCheck -eq $true) {
                    $UserDecision = Invoke-SelectionPrompt -Title "Node Complete" -Question "Do you want to proceed onto the next node?"
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

    if ($Stage.name -like "Completed") {
        Do {
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


            $Indexes = Get-EsIndex
            if ($ClosedHotIndexes) {
                write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Open Index | Begin opening indicies to restore production environment"
                
                $HotIndexes = $Indexes | Where-Object -FilterScript {($_.index -match 'logs-\d+') -and ($_.status -like 'open') -and ($_.rep -gt 0)} | Sort-Object index
                $HotIndexOpen = $HotIndexes.count
                $HotIndexClosed = $ClosedHotIndexes.count
                ForEach ($TargetIndex in $ClosedHotIndexes) {
                    write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Open Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize) | Opening Index: $($TargetIndex.Index)"
                    $OpenStatus = Open-EsIndex -Index $TargetIndex.Index
                    if ($OpenStatus.acknowledged) {
                        $HotIndexOpen += 1
                        $HotIndexClosed -= 1
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Open Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize) | Open Status: Completed"
                    } else {
                        write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Open Index | Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize) | Open Status: Incomplete"
                        write-host $OpenStatus
                    }
                }
            }

            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Manual Verification | Check Required: $($Stage.ManualCheck)"
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
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
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }
    
    # End Section - Start
    write-host "Status | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Rolling Restart | End Stage | Stage: $($Stage.Name)"
}