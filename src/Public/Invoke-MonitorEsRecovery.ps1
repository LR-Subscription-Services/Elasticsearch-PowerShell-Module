using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Invoke-MonitorEsRecovery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $False, Position = 0)]
        [string] $Title,

        [Parameter(Mandatory = $false, Position = 1)]
        [Int] $Sleep,

        [Parameter(Mandatory = $false, Position = 1)]
        [int] $MaxAttempts
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

    }

    Process {
        Do {
            $LastUnassigned = $($ClusterHealth.unassigned_shards)
            $ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($ClusterHealth.status)))

            if ($($ClusterHealth.number_of_nodes) -ne $ClusterNodesMax) {
                New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Unassigned Shards' -logExField1 'Cluster Nodes' -logMessage "Count: $($ClusterHealth.number_of_nodes) Target: $($ClusterNodesMax)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                
                $RetryMax += 5
            } else {
                $RetryCounter += 1
                $InitHistory.Add($($ClusterHealth.initializing_shards))

                $CurrentUnassigned = $($ClusterHealth.unassigned_shards)
                if ($CurrentUnassigned -ne $LastUnassigned) {
                    $RetryMax += 2
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                } else {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Unassigned Shards' -logExField1 'Recovery Stalled' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
                }
                $InitHistoryStats = $($InitHistory | Select-Object -Last 10 | Measure-Object -Maximum -Minimum -Sum -Average)
            }

            start-sleep $RetrySleep
        } until (($RetryCounter -ge $RetryMax) -or ($es_ClusterStatus -like "green") -or (($InitHistoryStats.count -eq $MaxInitConsecZero) -and ($InitHistoryStats.sum -eq 0)))
    }
}