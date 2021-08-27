using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Invoke-MonitorEsRecovery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, Position = 0)]
        [string] $Stage,

        [Parameter(Mandatory = $false, Position = 1)]
        [Int] $Sleep,

        [Parameter(Mandatory = $false, Position = 2)]
        [int] $MaxAttempts,

        [Parameter(Mandatory = $true, Position = 3)]
        [object] $Nodes
    )
    Begin {
        $InitHistory = [List[int]]::new()
        $TC = (Get-Culture).TextInfo
        If ($Sleep) {
            $RetrySleep = $Sleep
        } else {
            $RetrySleep = 5
        }

        if ($MaxAttempts) {
            $RetryMax = $MaxAttempts
        } else {
            $RetryMax = 20
        }

        $ClusterHealth = Get-EsClusterHealth
        $RetryCounter = 0
        $LastUnassigned = 0
        $CurrentUnassigned = 0

        $LastRecovery = $null
    }

    Process {
        Do {
            # Add sleep to this process for every iteration after the first.
            if ($RetryCounter -gt 0) {
                start-sleep $RetrySleep
            }
            # Increment the loop counter
            $RetryCounter += 1

            # Retrieve cluster health
            $LastUnassigned = $($ClusterHealth.unassigned_shards)

            # Capture previous Recovery counters if they are present as a variable
            if ($null -ne $CurrentRecovery) {
                $LastRecovery = $CurrentRecovery
            }

            $ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($ClusterHealth.status)))

            if ($es_ClusterStatus -like 'red') {
                $BadIndexes = Get-EsIndex | Where-Object -Property 'health' -like 'red'
                # Reset Columbo
                if ($BadIndexes.index -contains 'field_translations') {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -logExField1 'Recover Field Translation Indices' -logMessage "Performing index recovery"
                    Invoke-LrTransSyncReset -Node $Nodes[0].ipaddr
                }
                # Reset Carpenter
                if ((@($BadIndexes.index) -like 'emdb*').Count -gt 0) {
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -logExField1 'Recover EMDB Indices' -logMessage "Performing index recovery"
                    Invoke-LrEmdbSyncReset
                }
                #New-ProcessLog -logSev i -logStage $Stage -logStep 'Orphaned Shards' -logMessage "Sleeping for 30 seconds"
                #start-sleep 30
            }
            # Store initialization history
            $InitHistory.Add($($ClusterHealth.initializing_shards))

            # Update current Unassigned Shards details
            $CurrentUnassigned = $($ClusterHealth.unassigned_shards)

            # If we have initializing shards, begin tracking Elasticsearch Recovery
            if ($ClusterHealth.initializing_shards -gt 0) {
                $ESRecovery = Get-EsRecovery | Where-Object -Property 'stage' -NotLike 'done'
                if ($ESRecovery) {
                    $CurrentRecovery = $[PSCustomObject]@{
                        File = $ESRecovery.files_percent.replace('%','')
                        Bytes = $ESRecovery.bytes_percent.replace('%','')
                        Trans = $ESRecovery.translog_ops_percent.replace('%','')
                    }
                }
            }

            if ($null -ne $LastRecovery) {
                $FileDelta = $CurrentRecovery.File - $LastRecovery.File
                $BytesDelta = $CurrentRecovery.File - $LastRecovery.File
                $TransDelta = $CurrentRecovery.File - $LastRecovery.File

                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logExField2 'File Recovery    ' -logMessage "Current: $($CurrentRecovery.File)%  Last: $($LastRecovery.File)%  Progression:$FileDelta%"
                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logExField2 'Bytes Recovery   ' -logMessage "Current: $($CurrentRecovery.Bytes)%  Last: $($LastRecovery.Bytes)%  Progression:$BytesDelta%"
                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logExField2 'Translog Recovery' -logMessage "Current: $($CurrentRecovery.Trans)%  Last: $($LastRecovery.Trans)%  Progression:$TransDelta%"
                if ($CurrentRecovery -ne $LastRecovery) {
                    $RetryMax += 2
                    New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                } else {
                    if ($RetryCounter -eq 1) {
                        New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Starting   ' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                    } else {
                        New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Stalled    ' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                    }  
                }
            }
            $InitHistoryStats = $($InitHistory | Select-Object -Last 10 | Measure-Object -Maximum -Minimum -Sum -Average) 
        } until (($RetryCounter -ge $RetryMax) -or ($es_ClusterStatus -like "green") -or (($InitHistoryStats.count -eq $MaxInitConsecZero) -and ($InitHistoryStats.sum -eq 0)))
    }
}