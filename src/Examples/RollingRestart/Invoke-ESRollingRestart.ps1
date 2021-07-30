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

$RunAsServer = $es_ClusterHosts | Where-Object -Property 'hostname' -eq ${hostname}
if ($RunAsServer) {
    New-ProcessLog -logSev a -logStage 'Init' -logStep 'Restart Order' -logMessage "Removing restart management node from restart list.  Node: $($RunAsServer.hostname)"
    $RestartOrder.Remove($RunAsServer) | Out-Null
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
    IndexSize = 30
    Routing = "Primaries"
    Flush = $true
    ManualCheck = $true
})
$Stages.add([PSCustomObject]@{
    Name = "Running"
    ClusterStatus = "Yellow"
    SSH = $null
    IndexSize = 30
    Routing = "Primaries"
    MaxRetry = 30
    RetryWait = 15
    Flush = $false
    ManualCheck = $false
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
    if ($IndexSettings.transient.cluster.routing.allocation.enable -and $IndexSettings.transient.cluster.routing.allocation.enable -notlike $Stage.Routing) {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Current: $($IndexSettings.transient.cluster.routing.allocation.enable)  Target: $($Stage.Routing)"
        $tmp_VerifyAck = Update-EsIndexRouting -Enable $Stage.Routing
        if ($tmp_VerifyAck.acknowledged) {
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Set Cluster routing transient settings to target: $($tmp_VerifyAck.transient)"
        } else {
            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Cluster Routing' -logMessage "Unable to update cluster transient settings to target: $($Stage.Routing)"
        }
    } elseif ($IndexSettings.persistent.cluster.routing.allocation.enable -and $IndexSettings.persistent.cluster.routing.allocation.enable -notlike $Stage.Routing) {
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
    
    # Status to support validating transition to the next stage
    $TransitionStage = $false
    if ($Stage.name -Like "Pre") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            # Begin with validating remote access into the DX cluster's nodes
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "Target: $($Stage.SSH)"

            $rs_SessionStatus = Test-LrClusterRemoteAccess -HostNames $es_ClusterHosts.ipaddr
            ForEach ($rs_SessionStat in $rs_SessionStatus) {
                if ($rs_SessionStat.Id -eq -1) {
                    New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'SSH Verification' -logMessage "$($rs_SessionStat.Error)" -logExField1 "Session State: $($rs_SessionStat.State)" -logExField2 "Target: $($rs_SessionStat.ComputerName)"
                    
                    $RetryMax = 20
                    $RetrySleep = 5
                    $CurrentRetry = 0
                    Do {
                        start-sleep $RetrySleep
                        $rs_SessionStat = Test-LrClusterRemoteAccess -HostNames $rs_SessionStat.ComputerName
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
                Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder
            } else {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Health Validation' -logMessage "Current: $es_ClusterStatus  Target: $($Stage.ClusterStatus)"
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Health Validation' -logExField1 'End Step' -logMessage "Target Requirement Met"


            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Elasticsearch Rolling Restart" -Question "Are you sure you want to proceed?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'


            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                New-ProcessLog -logSev d -logStage $($Stage.Name) -logStep 'Pre Stage Iteration Delay' -logMessage "Sleeping for: $($IterationDelay)"
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)        
    }

    # Begin Section - Start
    if ($Stage.name -Like "Start") {
        Do {
            # Retrieve Cluster Status at the start of each stage's loop
            $es_ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
            $lr_ConsulLocks = Get-LrConsulLocks

            # Optional - Close down number of cluster indexes to reduce node recovery time
            if ($Stage.IndexSize -gt 0) {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Begin Step" -logMessage "Begin closing indicies to reduce recovery time requirements" 

                $HotIndexes = $Indexes | Where-Object -FilterScript {($_.index -match 'logs-\d+') -and ($_.status -like 'open') -and ($_.rep -gt 0)} | Sort-Object index
                if ($HotIndexes.count -le $stage.IndexSize) {
                    $TargetOpenIndexCount = 1
                } else {
                    $TargetOpenIndexCount = $HotIndexes.count - $Stage.IndexSize
                }
                $TargetClosedIndexes = $HotIndexes | Select-Object -First $TargetOpenIndexCount
                $HotIndexOpen = $HotIndexes.count
                $HotIndexClosed = $TargetClosedIndexes.count
                ForEach ($TargetIndex in $TargetClosedIndexes) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Index: $($TargetIndex.Index)"
                    
                    $CloseStatus = Close-EsIndex -Index $TargetIndex.Index
                    if ($CloseStatus.acknowledged) {
                        $HotIndexOpen -= 1
                        $HotIndexClosed += 1
                        $ClosedHotIndexes.add($TargetIndex)
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Completed"
                    } else {
                        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Close Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($Stage.IndexSize)" -logMessage "Closing Status: Incomplete"
                    }
                    
                }
            }

            <#
            $FlushSuccessSum = $FlushResults | Measure-Object -Property 'successful' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushFailSum = $FlushResults | Measure-Object -Property 'failed' -Sum | Select-Object -ExpandProperty 'Sum'
            $FlushTotal = $FlushResults | Measure-Object -Property 'total' -Sum | Select-Object -ExpandProperty 'Sum'
            write-host "Info | Stage: $($Stage.Name) | Health: $es_ClusterStatus | Step: Cluster Flush | Total Shards: $FlushTotal  Sucessful: $FlushSuccessSum  Failed: $FlushFailSum"
            #>
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'

            # Apply Stay Loop Delay if we're not aborting and not transitioning to the next phase
            if ($TransitionStage -eq $false -and $AbortStatus -eq $false) {
                start-sleep $IterationDelay
            }
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }

    # Begin Section - Start
    if ($Stage.name -Like "Running") {
        New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "Begin Stage"
        #Do {
            ForEach ($Node in $RestartOrder) {
                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "Begin Node" -logExField1 "Node: $($Node.hostname)"
                Do {
                    # Retrieve Cluster Status at the start of each stage's loop
                    $es_ClusterHealth = Get-EsClusterHealth
                    $es_ClusterStatus = $($TC.ToTitleCase($($es_ClusterHealth.status)))
                    $lr_ConsulLocks = Get-LrConsulLocks

                    # Add in restart to system here, using $($Node.ipaddr)
                    $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr)
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Cluster Flush' -logMessage "Submitting cluster flush to Elasticsearch" -logExField1 "Node: $($Node.hostname)"
                    $FlushResults = Invoke-EsFlushSync

                    if ($DryRun) {
                        $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {get-host}
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run Command' -logExField1 "Node: $($Node.hostname)" -logExField2 "Command: get-host" -logMessage "PSComputerName: $($HostResult.PSComputerName)   RunSpace: $($HostResult.Name)"
                    } else {
                        $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {bash -c "sudo shutdown -r now"} -ErrorAction SilentlyContinue
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run Command' -logExField1 "Node: $($Node.hostname)" -logMessage "Command: restart-computer"
                        Start-Sleep 10
                    }
                    #If ($NodeSession.GetStatus here)
                    $Count = 0
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -logExField1 "Node: $($Node.hostname)" -logMessage "Begin monitoring host online/offline status"
                    do {
                        $Count += 1
                        $HostOnline = Test-Connection -Ipv4 $($Node.ipaddr) -Quiet
                        
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Host Status' -logExField1 "Node: $($Node.hostname)" -logMessage "Status: $($HostOnline)"
                        Start-Sleep $($Stage.RetryWait)
                    } until ($HostOnline = $true -or $Count -ge $($Stage.MaxRetry))
                    
                    if ($Count -ge $($Stage.MaxRetry)) {
                        New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Host Status' -logExField1 "Node: $($Node.hostname)" -logMessage "Test-Connection Max retries reached"
                        $AlertCheck -eq $true
                    } else {
                        Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder
                    }
                    
                    
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField2 'Begin Step' -logExField1 "Node: $($Node.hostname)"
                    if ($Stage.ManualCheck -eq $true -or $AlertCheck -eq $true) {
                        $UserDecision = Invoke-SelectionPrompt -Title "Node Complete" -Question "Do you want to proceed onto the next node?"
                        if ($UserDecision -eq 0) {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Manual authorization granted.  Proceeding to next stage." -logExField1 "Node: $($Node.hostname)"
                            $TransitionStage = $true
                        } else {
                            New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Aborting rolling restart process due to manual halt." -logExField1 "Node: $($Node.hostname)"
                            $AbortStatus = $true
                        }
                    } else {
                        $TransitionNode -eq $true
                    }
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField2 'End Step' -logExField1 "Node: $($Node.hostname)"
                } While ($TransitionNode -eq $false -and $AbortStatus -eq $false)

                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "End Node" -logExField1 "Node: $($Node.hostname)"
            }

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }

        #} While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
        New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Restart Node' -logMessage "End Stage"
    }

    if ($Stage.name -like "Completed") {
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
                $HotIndexOpen = $HotIndexes.count
                $HotIndexClosed = $ClosedHotIndexes.count
                ForEach ($TargetIndex in $ClosedHotIndexes) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Opening Index: $($TargetIndex.Index)"
                    $OpenStatus = Open-EsIndex -Index $TargetIndex.Index
                    if ($OpenStatus.acknowledged) {
                        $HotIndexOpen += 1
                        $HotIndexClosed -= 1
                        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Completed" 
                        Invoke-MonitorEsRecovery -Stage $Stage.Name -Nodes $RestartOrder
                    } else {
                        New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "Open:$HotIndexOpen Closed:$($HotIndexClosed) Target:$($($ClosedHotIndexes.count)+$IndexSize)" -logMessage "Open Status: Incomplete" 
                    }
                }
                New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Open Index' -logExField1 "End Step" -logMessage "Opening hot indicies to restore production environment state."
            }

            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'Begin Step'
            if ($Stage.ManualCheck -eq $true) {
                $UserDecision = Invoke-SelectionPrompt -Title "Stage Complete" -Question "Do you want to proceed onto the next stage?"
                if ($UserDecision -eq 0) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Manual authorization granted.  Proceeding to next stage."
                    $TransitionStage = $true
                } else {
                    New-ProcessLog -logSev a -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Aborting rolling restart process due to manual halt."
                    $AbortStatus = $true
                }
            } else {
                $TransitionStage -eq $true
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Manual Verification' -logMessage "Check Required: $($Stage.ManualCheck)" -logExField1 'End Step'
        } While ($TransitionStage -eq $false -and $AbortStatus -eq $false)
    }
    New-ProcessLog -logSev s -logStage $($Stage.Name) -logStep 'Rolling Restart' -logMessage "Stage: $($Stage.Name)" -logExField1 "End Stage"
}