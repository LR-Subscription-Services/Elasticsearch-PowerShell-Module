using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Invoke-MonitorEsRecovery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False, Position = 0)]
        [string] $Stage = "Manual",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int] $Sleep,

        [Parameter(Mandatory = $false, Position = 2)]
        [int] $MaxAttempts = -1,

        [Parameter(Mandatory = $false, Position = 3)]
        [object] $Nodes,

        [Parameter(Mandatory = $false, Position = 4)]
        [object] $CurrentNode
    )
    Begin {
        $TC = (Get-Culture).TextInfo
        If ($Sleep) {
            $RetrySleep = $Sleep
        } else {
            $RetrySleep = 5
        }

        if ($MaxAttempts) {
            $RetryMax = $MaxAttempts
        } else {
            $RetryMax = 200
        }

        if ($null -eq $CurrentNode) {
            $CurrentNode = [PSCustomObject]@{
                Hostname = [System.Net.Dns]::GetHostName()
            }
        }

        $ClusterHealth = Get-EsClusterHealth
        $RetryCounter = 0
        $LastUnassigned = 0
        $CurrentUnassigned = 0

        $RecoveryList = $null
        $LastRecovery = [List[object]]::new()
    }

    Process {
        Do {
            # Retrieve cluster health
            $LastUnassigned = $($ClusterHealth.unassigned_shards)

            # Capture previous Recovery counters if they are present as a variable
            if ($null -ne $RecoveryList) {
                $LastRecovery = $RecoveryList
            }

            $ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($ClusterHealth.status)))

            if ($es_ClusterStatus -like 'red') {
                $BadIndexes = Get-EsIndex | Where-Object -Property 'health' -like 'red'
                # Reset Columbo
                if ($BadIndexes.index -contains 'field_translations') {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recover Field Translation Indices' -logMessage "Performing index recovery"
                    Invoke-LrTransSyncReset -Node $Nodes[0].ipaddr
                }
                # Reset Carpenter
                if ((@($BadIndexes.index) -like 'emdb*').Count -gt 0) {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recover EMDB Indices' -logMessage "Performing index recovery"
                    Invoke-LrEmdbSyncReset
                }
                #New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -logMessage "Sleeping for 30 seconds"
                #start-sleep 30
            }
            
            # Update current Unassigned Shards details
            $CurrentUnassigned = $($ClusterHealth.unassigned_shards)

            if ($CurrentUnassigned -gt 0 -and ($CurrentUnassigned -eq $LastUnassigned)) {
                # Granular inspection of recovery progress
                $ESRecovery = Get-EsRecovery | Sort-Object index
                if ($ESRecovery) {
                    $RecoveryList = [List[object]]::new()
                    :RecoveryIndex ForEach ($Index in $($ESRecovery | Sort-Object 'index' -Unique | Select-Object -ExpandProperty 'index')) {
                        $IndexRecovery = $ESRecovery | Where-Object -Property 'stage' -NotLike 'done' | Where-Object -Property 'index' -like $Index
                        if ($IndexRecovery) {
                            $IndexRecoveryAggregate = [PSCustomObject]@{
                                Index = $Index
                                Shards = $IndexRecovery.count
                                File = [math]::Round($($IndexRecovery.files_percent.replace('%','') | Measure-Object -Average | Select-Object -ExpandProperty Average),2)
                                Bytes = [math]::Round($($IndexRecovery.bytes_percent.replace('%','') | Measure-Object -Average | Select-Object -ExpandProperty Average),2)
                                Trans = [math]::Round($($IndexRecovery.translog_ops_percent.replace('%','') | Measure-Object -Average | Select-Object -ExpandProperty Average),2)
                            }
                            $RecoveryList.add($IndexRecoveryAggregate)
                        } else {
                            continue RecoveryIndex
                        }
                    }
                    if ($null -ne $LastRecovery) {
                        ForEach ($Recovery in $RecoveryList) {
                            New-ProcessLog -logSev i -logStage $Stage -logStep 'Recovery Progress' -Node $($CurrentNode.hostname) -index $($Recovery.Index) -logExField1 "Shards: $($Recovery.Shards)" -logMessage "File: $($Recovery.File)%  Bytes: $($Recovery.Bytes)%  Translog: $($Recovery.Trans)%" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                        }

                        # Print a Unassigned Shard status update periodically.
                        if (($RetryCounter % 5) -eq 0) {
                            if ($RecoveryList -ne $LastRecovery) {
                                if ($RetryMax -ne -1) {
                                    $RetryMax += 1
                                }
                                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Progress' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                            } else {
                                if ($RetryCounter -eq 1) {
                                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Starting' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                                } else {
                                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Stalled' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                                }
                            }
                        }
                    }
                }
            } elseif ($CurrentUnassigned -gt 0 -and ($CurrentUnassigned -ne $LastUnassigned)) {
                # Higher level overview of recovery progress
                if ($RetryMax -ne -1) {
                    $RetryMax += 1
                }
                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Progress' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
            } else {
                if ($RetryCounter -eq 1) {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Starting' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                } else {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -Node $($CurrentNode.hostname) -logExField1 'Recovery Stalled' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)" -logRetryMax $RetryMax -logRetryCurrent $RetryCounter
                }
            }


            if (($RetryCounter % 5) -eq 0) {
                start-sleep $RetrySleep
            } else {
                # Add sleep to this process for every iteration after the first.
                if ($RetryCounter -gt 0) {
                    [int32]$HalfSleep = $RetrySleep / 2
                    start-sleep -Seconds $HalfSleep
                }
            }

            # Increment the loop counter
            # If the MaxRetry is set to -1, retry indefinently.
            if ($RetryMax -eq -1) {
                $RetryCounter = 0
            } else {
                $RetryCounter += 1
            }
        } until ((($RetryCounter -ge $RetryMax) -and ($RetryMax -ne -1)) -or ($es_ClusterStatus -like "green"))
    }
}