using namespace System
using namespace System.IO
using namespace System.Collections.Generic

$SSHKey = '~/.ssh/id_ecdsa'

# User driven command variables, where a user can inject OS commands in any of the stages.
$Pre_UserCommands = [List[string]]::new()
$Start_UserCommands = [List[string]]::new()
$Running_UserCommands = [List[string]]::new()
$Completed_UserCommands = [List[string]]::new()
$End_UserCommands = [List[string]]::new()

$Running_UserCommands.add('sudo yum update -y')

# Timers to work into 1.5
# 
# Entire runtime
# Time to complete each Stage
# Time to complete each Node
# Time to reboot/return online

# Show my last update (Cluster view / Node View)

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

$RunAsServer = $es_ClusterHosts | Where-Object -Property 'hostname' -eq $(Invoke-Command -ScriptBlock {bash -c "hostname"})
if ($RunAsServer) {
    New-ProcessLog -logSev a -logStage 'Init' -logStep 'Restart Order' -logMessage "Removing restart management node from restart list.  Node: $($RunAsServer.hostname)"
    $RestartOrder.Remove($RunAsServer) | Out-Null
}

# Verify SSH key established
#$(Invoke-Command -ScriptBlock {bash -c "eval `"`$(ssh-agent)`""})
$(Invoke-Command -ScriptBlock {bash -c "ssh-add $SSHKey"})

$SSHConfigStatus = Add-LrHostSSHConfig -Path '/home/logrhythm/.ssh/config'

# List of index that are closed as part of auto rolling restart to be re-opened in the Completed stage
$ClosedHotIndexes = [List[object]]::new()

# Master Last
# -- Master Data Node

$Stages = [List[object]]::new()
$Stages.add([PSCustomObject]@{
    Name = "Configuration"
    ClusterStatus = "Green"
    ClusterHosts = $(Get-LrClusterHosts)
    SSH = "Verify"
    IndexSize = -1
    Bulk_Open = 1
    Bulk_Close = 10
    Routing = "all"
    MaxRetry = 40
    RetryWait = 15
    NodeDelayTimeout = $null
    Flush = $false
    ManualCheck = $true
    UserCommands = $Pre_UserCommands
})
$Stages.add([PSCustomObject]@{
    Name = "Initialize"
    ClusterStatus = "Green"
    SSH = $null
    IndexSize = -1
    Bulk_Open = 1
    Bulk_Close = 10
    Routing = "new_primaries"
    MaxRetry = 40
    RetryWait = 15
    NodeDelayTimeout = 60
    Flush = $true
    ManualCheck = $false
    UserCommands = $Start_UserCommands
})
$Stages.add([PSCustomObject]@{
    Name = "Executing"
    ClusterStatus = "Yellow"
    SSH = $null
    IndexSize = 5
    Bulk_Open = 2
    Bulk_Close = 10
    Routing = "new_primaries"
    MaxRetry = 90
    RetryWait = 5
    NodeDelayTimeout = $null
    Flush = $false
    ManualCheck = $false
    UserCommands = $Running_UserCommands
})
$Stages.add([PSCustomObject]@{
    Name = "Verify"
    ClusterStatus = "Green"
    SSH = $null
    IndexSize = -1
    Bulk_Open = 4
    Bulk_Close = 10
    Routing = "all"
    MaxRetry = 40
    RetryWait = 15
    NodeDelayTimeout = 300
    Flush = $false
    ManualCheck = $false
    UserCommands = $Completed_UserCommands
})
$Stages.add([PSCustomObject]@{
    Name = "Complete"
    ClusterStatus = "Green"
    SSH = "Verify"
    IndexSize = -1
    Bulk_Open = 10
    Bulk_Close = 10
    Routing = "all"
    MaxRetry = 40
    RetryWait = 15
    NodeDelayTimeout = $null
    Flush = $false
    ManualCheck = $false
    UserCommands = $End_UserCommands
})



# Status to support aborting at the transition point from the exit of one process tage prior to beginning the next stage
$AbortStatus = $false
$DryRun = $false

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
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Abort Status' -logMessage "Abort Status set to $($AbortStatus).  Aborting Rolling Restart Automation."
        break
    }
    New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Rolling Restart' -logMessage "Stage: $($Stage.Name)" -logExField1 "Begin Stage"

    # Seed common cluster data
    Try {
        $IndexStatus = Get-EsIndexStatus
        New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Index Status' -logMessage "Successfully retrieved Index Status in variable IndexStatus"
    } Catch {
        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Index Status' -logMessage "Unable to retrieve Index Status in variable IndexStatus"
    }
    
    Try {
        $IndexSettings = Get-EsSettings
        New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Index Settings' -logMessage "Successfully retrieved Index Settings in variable IndexSettings"
    } Catch {
        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Index Settings' -logMessage "Unable to retrieve Index Settings in variable IndexSettings"
    }
    
    Try {
        $Indexes = Get-EsIndex
        New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Index Catalog' -logMessage "Successfully retrieved Indexes in variable Indexes"
    } Catch {
        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Index Catalog' -logMessage "Unable to retrieve Indexes in variable Indexes"
    }

    # Global Processes to complete on each stage
    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Target: $($Stage.Routing)" -logExField1 'Begin'

    # If the current stage does not have the Shard allocation enabed, update the transient cluster routing to target to support cluster health recovery
    # This check inspects the current transient/temporary setting applied to the DX cluster
    if ($IndexSettings.transient.cluster.routing.allocation.enable -and ($IndexSettings.transient.cluster.routing.allocation.enable -notlike $Stage.Routing)) {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Current: $($IndexSettings.transient.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
        $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
        if ($tmp_VerifyAck.acknowledged) {
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
        } else {
            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Unable to update cluster transient settings to target: $($Stage.Routing)"
        }
    } elseif ($IndexSettings.persistent.cluster.routing.allocation.enable -and ($IndexSettings.persistent.cluster.routing.allocation.enable -notlike $Stage.Routing)) {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Current: $($IndexSettings.persistent.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
        $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
        if ($tmp_VerifyAck.acknowledged) {
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
        } else {
            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Unable to update cluster transient settings to target: $($Stage.Routing)"
        }
    } else {
        if ($IndexSettings.transient.cluster.routing.allocation.enable) {
            $CurrentEsRouting = $IndexSettings.transient.cluster.routing.allocation.enable
        } else {
            $CurrentEsRouting = $IndexSettings.persistent.cluster.routing.allocation.enable
        } 
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Current: $CurrentEsRouting Target: $($Stage.Routing)"
    }
    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Target: $($Stage.Routing)" -logExField1 'End'

    
    if ($Stage.UserCommands.count -ge 1) {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'User Commands' -logMessage "Command Count: $($Stage.UserCommands.count)" -logExField1 'Begin' 
        Invoke-RunUserCommand -Commands $Stage.UserCommands -Nodes $RestartOrder -Stage $($Stage.Name) -SSHKeyPath $SSHKey
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'User Commands' -logMessage "Command Count: $($Stage.UserCommands.count)" -logExField1 'End'
    }
    

    if ($Stage.NodeDelayTimeout) {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Recovery Delay Timeout' -logExField1 "Begin Step" -logMessage "Setting ElasticSearch Node Timeout Delay to $($Stage.NodeDelayTimeout) seconds" 
        $UpdateVerify = Update-EsNodeDelayTimeout -Value $Stage.NodeDelayTimeout -Type 's'
        if ($UpdateVerify.acknowledged) {
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Recovery Delay Timeout' -logMessage "Successfully updated Node Timeout Delay"
        } else {
            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Recovery Delay Timeout' -logMessage "Unable to update Node Timeout Delay"
        }
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Recovery Delay Timeout' -logExField1 "End Step" -logMessage "Setting ElasticSearch Node Timeout Delay to $($Stage.NodeDelayTimeout) seconds" 
    }

    # Status to support validating transition to the next stage
    $TransitionStage = $false
    if ($Stage.name -Like "Configuration") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            # Begin with validating remote access into the DX cluster's nodes
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "Target: $($Stage.SSH)"

            $rs_SessionStatus = Test-LrClusterRemoteAccess -HostNames $es_ClusterHosts.ipaddr -Path $SSHKey
            ForEach ($rs_SessionStat in $rs_SessionStatus) {
                if ($rs_SessionStat.Id -eq -1) {
                    New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "$($rs_SessionStat.Error)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                    
                    $RetryMax = 20
                    $RetrySleep = 5
                    $CurrentRetry = 0
                    Do {
                        start-sleep $RetrySleep
                        $rs_SessionStat = Test-LrClusterRemoteAccess -HostNames $rs_SessionStat.ComputerName -Path $SSHKey
                        if ($rs_SessionStat.Id -eq -1) {
                            $CurrentRetry += 1
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "$($rs_SessionStat.Error)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                        } else {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "Session ID: $($rs_SessionStat.Id)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                        }
                    } until (($CurrentRetry -ge $RetryMax) -or ($rs_SessionStat.State -like "Opened"))
                } else {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "Session ID: $($rs_SessionStat.Id)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                }
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "Target: $($Stage.SSH)"

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

            # Monitor Cluster Recovery
            if ($es_ClusterStatus -notlike "green") {
                New-ProcessLog -logSev w -logStage $($Stage.Name) -logStep 'Cluster Health Validation' -logMessage "Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
                Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder -Sleep $Stage.RetryWait -MaxAttempts $Stage.MaxRetry
            } else {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Health Validation' -logMessage "Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Health Validation' -logExField1 'End Step' -logMessage "Target Requirement Met"

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Elasticsearch Rolling Restart" -Question "Are you sure you want to proceed?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage = $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'


            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Pre Stage Iteration Delay' -logMessage "Sleeping for: $($IterationDelay)"
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)        
    }

    # Begin Section - Init
    if ($Stage.name -Like "Initialize") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage = $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'

            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }

    # Begin Section - Start
    if ($Stage.name -Like "Executing") {
        New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "Begin Stage"
        #Do {
            ForEach ($Node in $RestartOrder) {
                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -Node $($Node.hostname) -logMessage "Begin Node"

                Try {
                    $Indexes = Get-EsIndex
                    New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Index Catalog' -logMessage "Successfully retrieved Indexes in variable Indexes"
                } Catch {
                    New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Index Catalog' -logMessage "Unable to retrieve Indexes in variable Indexes"
                }

                # Optional - Close down number of cluster indexes to reduce node recovery time
                if ($Node.type -like 'hot') {
                    if ($Stage.IndexSize -gt 0) {
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Begin Step" -logMessage "Begin closing indicies to reduce recovery time requirements" 

                        $HotIndexes = $Indexes | Where-Object -FilterScript {($_.index -match 'logs-\d+') -and ($_.status -like 'open') -and ($_.rep -gt 0)} | Sort-Object index
                        if ($HotIndexes.count -le $Stage.IndexSize) {
                            $TargetOpenIndexCount = 1
                        } else {
                            $TargetOpenIndexCount = $HotIndexes.count - $Stage.IndexSize
                        }

                        # Reduce target indexes to the quantity defined.
                        $TargetClosedIndexes = $HotIndexes | Select-Object -First $TargetOpenIndexCount
                        
                        # Establish an array of an array of target indexes to support bulk close operations
                        if ($Stage.Bulk_Close -le 0) {
                            $CloseIndexSegments =  Split-ArraySegments -InputArray $TargetClosedIndexes -Segments 1
                        } else {
                            # Default to one segment if Bulk_Close >= TargetIndexCount
                            if ($Stage.Bulk_Close -ge $TargetClosedIndexes.count) {
                                [int32]$SegmentCount = 1
                            } else {
                                [int32]$SegmentCount = $TargetClosedIndexes.count / $Stage.Bulk_Close
                            }
                            $CloseIndexSegments =  Split-ArraySegments -InputArray $TargetClosedIndexes -Segments $SegmentCount
                        }
                        

                        $HotIndexOpen = $HotIndexes.count
                        $HotIndexClosed = $TargetClosedIndexes.count
                        if ($CloseIndexSegments.count -gt 1) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "Begin Step"
                            ForEach ($TargetIndices in $CloseIndexSegments) {
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing bulk indices: $($TargetIndices.count)"
                                $Indices = $([String]::Join(",",$TargetIndices.index))
                                $CloseStatus = Close-EsIndex -Index $Indices

                                
                                if ($CloseStatus.acknowledged) {
                                    $HotIndexOpen -= $TargetIndices.count
                                    $HotIndexClosed += $TargetIndices.count
        
                                    ForEach ($Index in $TargetIndices) {
                                        $ClosedHotIndexes.add($Index)
                                    }                            
                                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Completed"
                                } else {
                                    New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Incomplete"
                                }
                            }
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "End Step"
                        } else {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "Begin Step"
                            ForEach ($TargetIndices in $CloseIndexSegments) {
                                ForEach ($Index in $TargetIndices) {
                                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Index: $($Index.Index)"
                                    $CloseStatus = Close-EsIndex -Index $Index.index
                                
                                    if ($CloseStatus.acknowledged) {
                                        $HotIndexOpen -= 1
                                        $HotIndexClosed += 1
            
                                        ForEach ($Index in $TargetIndices) {
                                            $ClosedHotIndexes.add($Index)
                                        }                            
                                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Completed"
                                    } else {
                                        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Incomplete"
                                    }
                                }
                            }
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "End Step"
                        }
                    }
                }

                if ($Node.type -like 'warm') {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Warm Node Indices' -Node $($Node.hostname) -logMessage "Reviewing warm nodes for any open indices"
                    $OpenWarmIndices = Get-EsIndex | Where-Object -FilterScript {($_.status -like 'open') -and ($_.rep -eq 0)}
                    $WarmIndexClosed = 0
                    $WarmIndexOpen = $OpenWarmIndices.index.count

                    if ($null -ne $OpenWarmIndices) {
                        # Establish an array of an array of target indexes to support bulk close operations
                        if ($Stage.Bulk_Close -le 0) {
                            $CloseIndexSegments =  Split-ArraySegments -InputArray $TargetClosedIndexes -Segments 1
                        } else {
                            # Default to one segment if Bulk_Close >= TargetIndexCount
                            if ($Stage.Bulk_Close -ge $OpenWarmIndices.count) {
                                [int32]$SegmentCount = 1
                            } else {
                                [int32]$SegmentCount = $OpenWarmIndices.count / $Stage.Bulk_Close
                            }
                            $CloseIndexSegments =  Split-ArraySegments -InputArray $OpenWarmIndices -Segments $SegmentCount
                        }

                        if ($CloseIndexSegments.count -gt 1) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "Begin Step"
                            ForEach ($TargetIndices in $CloseIndexSegments) {
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$WarmIndexOpen Closed:$($WarmIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing bulk indices: $($TargetIndices.count)"
                                $Indices = $([String]::Join(",",$TargetIndices.index))
                                $CloseStatus = Close-EsIndex -Index $Indices
                                
                                if ($CloseStatus.acknowledged) {
                                    $WarmIndexOpen -= $TargetIndices.count
                                    $WarmIndexClosed += $TargetIndices.count

                                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$WarmIndexOpen Closed:$($WarmIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing Status: Completed"
                                } else {
                                    New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$WarmIndexOpen Closed:$($WarmIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing Status: Incomplete"
                                }
                            }
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "End Step"
                        } else {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "Begin Step"
                            ForEach ($TargetIndices in $CloseIndexSegments) {
                                ForEach ($Index in $TargetIndices) {
                                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$WarmIndexOpen Closed:$($WarmIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing Index: $($Index.Index)"
                                    $CloseStatus = Close-EsIndex -Index $Index.index
                                
                                    if ($CloseStatus.acknowledged) {
                                        $HotIndexOpen -= 1
                                        $HotIndexClosed += 1                          
                                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing Status: Completed"
                                    } else {
                                        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$WarmIndexClosed" -logMessage "Closing Status: Incomplete"
                                    }
                                }
                            }
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index - Mode' -logMessage "Segment Count: $($CloseIndexSegments.count)" -logExField1 "End Step"
                        }
                    }
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Warm Node Indices' -Node $($Node.hostname) -logMessage "Open indices review complete"
                }

                Do {
                    # Retrieve Cluster Status at the start of each stage's loop
                    $es_ClusterHealth = Get-EsClusterHealth
                    $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
                    $lr_ConsulLocks = Get-LrConsulLocks

                    # Update cluster routing to Primaries before node reboot
                    $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
                    if ($tmp_VerifyAck.acknowledged) {
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -Node $($Node.hostname) -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
                    } else {
                        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Cluster Routing' -Node $($Node.hostname) -logMessage "Unable to update cluster transient settings to target: $($Stage.Routing)"
                    }

                    # Add in restart to system here, using $($Node.ipaddr)
                    $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr) -Path $SSHKey
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Flush' -Node $($Node.hostname) -logMessage "Submitting cluster flush to Elasticsearch"
                    $FlushResults = Invoke-EsFlushSync

                    if ($DryRun) {
                        $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {get-host}
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run Command' -Node $($Node.hostname) -logExField2 "Command: get-host" -logMessage "PSComputerName: $($HostResult.PSComputerName)   RunSpace: $($HostResult.Name)"
                    } else {
                        Try {
                            $BaseUptime = Invoke-Command -Session $NodeSession -ScriptBlock {get-uptime}
                        } Catch {
                            write-host $_
                        }
                        
                        if ($null -ne $BaseUptime) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Current Uptime: $($BaseUptime.tostring())"
                            $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {bash -c "sudo shutdown -r now"} -ErrorAction SilentlyContinue

                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run Command' -Node $($Node.hostname) -logMessage "Command: restart-computer"
                            
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Offline" -logMessage "Begin monitoring host online/offline status." 
                            Do {
                                $CurrentUptime = $null
                                $HostOnline = Test-Connection -Ipv4 $($Node.ipaddr) -Quiet
                                if ($HostOnline) {
                                    $HostOnlineStatus = "Online"
                                    Try {
                                        $CurrentUptime = Invoke-Command -Session $NodeSession -ScriptBlock {get-uptime} -ErrorAction SilentlyContinue
                                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Current Uptime: $($CurrentUptime.tostring())"
                                    } Catch {
                                        
                                    }
                                    if ((($null -ne $CurrentUptime) -and ($CurrentUptime -lt $BaseUptime))) {
                                        # Host has rebooted, very quickly!
                                        $HostOnlineStatus = "Offline"
                                    }
                                } else {
                                    $HostOnlineStatus = "Offline"
                                }
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Offline" -logMessage "Status: $HostOnlineStatus"
                                Start-Sleep $($Stage.RetryWait / 5)
                            } Until (!$HostOnline)

                            if (!$HostOnline) {
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Offline" -logMessage "Target requirement met.  Node unreachable." 
                            }
                        }
                    }

                    $Count = 0
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Online" -logMessage "Begin monitoring host online/offline status." 
                    do {
                        $Count += 1
                        $HostOnline = Test-Connection -Ipv4 $($Node.ipaddr) -Quiet
                        if ($HostOnline) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Online" -logMessage "Status: Online"
                            $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr) -Path $SSHKey
                            if ($NodeSession.Availability -like "Available") {
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Node reachable with SSH authentication."
                                Try {
                                    $CurrentUptime = Invoke-Command -Session $NodeSession -ScriptBlock {get-uptime} -ErrorAction SilentlyContinue
                                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Current Uptime: $($CurrentUptime.tostring())"
                                } Catch {
                                    $_
                                }
                            } else {
                                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Node reachable.  Unable to authenticate."    
                            }
                        } else {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logExField1 "Target: Online" -logMessage "Status: Offline"
                        }
                        Start-Sleep $($Stage.RetryWait)
                    } until ((($null -ne $CurrentUptime) -and ($CurrentUptime -lt $BaseUptime)) -or ($Count -ge $($Stage.MaxRetry)))
                    
                    if ($Count -ge $($Stage.MaxRetry)) {
                        New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Max retries reached"
                        $AlertCheck -eq $true
                    } else {
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -Node $($Node.hostname) -logMessage "Beginning recovery"
                        $tmp_VerifyAck = Update-EsIndexRouting -Enable 'all'
                        if ($tmp_VerifyAck.acknowledged) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -Node $($Node.hostname) -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
                        } else {
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Cluster Routing' -Node $($Node.hostname) -logMessage "Unable to update cluster transient settings to target: all"
                        }

                        Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder -CurrentNode $Node -Sleep $Stage.RetryWait -MaxAttempts $Stage.MaxRetry
                    }
                                        
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -Node $($Node.hostname) -logMessage "Check Required: $($Stage.ManualCheck)" -logExField2 'Begin Step' -logExField1 "Node: $($Node.hostname)"
                    if ($Stage.ManualCheck -eq $true -or $AlertCheck -eq $true) {
                        $UserDecision = Invoke-SelectionPrompt -Title "Node Complete" -Question "Do you want to proceed onto the next node?"
                        if ($UserDecision -eq 0) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -Node $($Node.hostname) -logMessage "Manual authorization granted.  Proceeding to next stage." -logExField1 "Node: $($Node.hostname)"
                            $TransitionStage = $true
                        } else {
                            New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -Node $($Node.hostname) -logMessage "Aborting rolling restart process due to manual halt." -logExField1 "Node: $($Node.hostname)"
                            $AbortStatus = $true
                        }
                    } else {
                        $TransitionNode = $true
                    }
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -Node $($Node.hostname) -logMessage "Check Required: $($Stage.ManualCheck)" -logExField2 'End Step' -logExField1 "Node: $($Node.hostname)"
                } While ($TransitionNode -eq $false -and $AbortStatus -eq $false)

                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -Node $($Node.hostname) -logMessage "End Node" 
            }

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage = $true
            }

        #} While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
        New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "End Stage"
    }

    if ($Stage.name -like "Verify") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            $IndexStatus = Get-EsIndexStatus
            $IndexSettings = Get-EsSettings

            $Indexes = Get-EsIndex
            if ($ClosedHotIndexes) {
                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Begin Step" -logMessage "Opening hot indicies to restore production environment state."

                $HotIndexes = $Indexes | Where-Object -FilterScript {($_.index -match 'logs-\d+') -and ($_.status -like 'open') -and ($_.rep -gt 0)} | Sort-Object index              
                $TargetOpenIndexes = $ClosedHotIndexes
                    
                # Establish an array of an array of target indexes to support bulk close operations
                if ($Stage.Bulk_Open -le 0) {
                    $OpenIndexSegments =  Split-ArraySegments -InputArray $TargetOpenIndexes -Segments 1
                } else {
                    if ($Stage.Bulk_Open -ge $TargetOpenIndexes.count) {
                        [int32]$SegmentCount = 1
                    } else {
                        [int32]$SegmentCount = $TargetOpenIndexes.count / $Stage.Bulk_Open
                    }
                    
                    $OpenIndexSegments =  Split-ArraySegments -InputArray $TargetOpenIndexes -Segments $SegmentCount
                }
                

                $HotIndexOpen = $HotIndexes.count
                $HotIndexClosed = $TargetOpenIndexes.count
                if ($OpenIndexSegments.count -gt 1) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index - Mode' -logMessage "Segment Size: $($OpenIndexSegments.count)" -logExField1 "Begin Step"
                    ForEach ($TargetIndices in $OpenIndexSegments) {
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open bulk indices: $($TargetIndices.count)"
                        $Indices = $([String]::Join(",",$TargetIndices.index))
                        $OpenStatus = Open-EsIndex -Index $Indices

                    
                        if ($OpenStatus.acknowledged) {
                            $HotIndexOpen += $TargetIndices.count
                            $HotIndexClosed -= $TargetIndices.count
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Completed" 
                            Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder -Sleep $Stage.RetryWait -MaxAttempts $Stage.MaxRetry
                        } else {
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Incomplete" 
                        }
                    }
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index - Mode' -logMessage "Segment Size: $($OpenIndexSegments.count)" -logExField1 "End Step"
                } else {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index - Mode' -logMessage "Segment Size: $($OpenIndexSegments.count)" -logExField1 "Begin Step"
                    ForEach ($TargetIndices in $OpenIndexSegments) {
                        ForEach ($TargetIndex in $TargetIndices) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Opening Index: $($TargetIndex.index)"
                            $OpenStatus = Open-EsIndex -Index $TargetIndex.index
                        }
                    
                        if ($OpenStatus.acknowledged) {
                            $HotIndexOpen += 1
                            $HotIndexClosed -= 1
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Completed" 
                            Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder -Sleep $Stage.RetryWait -MaxAttempts $Stage.MaxRetry
                        } else {
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Incomplete" 
                        }
                    }
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index - Mode' -logMessage "Segment Size: $($OpenIndexSegments.count)" -logExField1 "End Step"
                }
                
                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "End Step" -logMessage "Opening hot indicies to restore production environment state."
            }

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage = $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }

    if ($Stage.name -like "Complete") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            $IndexStatus = Get-EsIndexStatus
            $IndexSettings = Get-EsSettings

            $Indexes = Get-EsIndex

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage = $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verify' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }
    New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Rolling Restart' -logMessage "Stage: $($Stage.Name)" -logExField1 "End Stage"
}
Remove-LrHostSSHConfig -Path '/home/logrhythm/.ssh/config' -Action $SSHConfigStatus.Action