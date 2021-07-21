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
            # Add sleep to this process for every iteration after the first.
            if ($RetryCounter -gt 0) {
                start-sleep $RetrySleep
            }
            # Increment the loop counter
            $RetryCounter += 1

            # Retrieve cluster health
            $LastUnassigned = $($ClusterHealth.unassigned_shards)
            $ClusterHealth = Get-EsClusterHealth
            $es_ClusterStatus = $($TC.ToTitleCase($($ClusterHealth.status)))

            # Store initialization history
            $InitHistory.Add($($ClusterHealth.initializing_shards))

            # Update current Unassigned Shards details
            $CurrentUnassigned = $($ClusterHealth.unassigned_shards)
            if ($CurrentUnassigned -ne $LastUnassigned) {
                $RetryMax += 2
                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Progression' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
            } else {
                New-ProcessLog -logSev i -logStage $Stage -logStep 'Unassigned Shards' -logExField1 'Recovery Stalled' -logMessage "Unassigned: $($ClusterHealth.unassigned_shards)  Initializing: $($ClusterHealth.initializing_shards)  Attempt: $RetryCounter  Remaining: $($RetryMax - $RetryCounter)"
            }
            $InitHistoryStats = $($InitHistory | Select-Object -Last 10 | Measure-Object -Maximum -Minimum -Sum -Average) 
        } until (($RetryCounter -ge $RetryMax) -or ($es_ClusterStatus -like "green") -or (($InitHistoryStats.count -eq $MaxInitConsecZero) -and ($InitHistoryStats.sum -eq 0)))
    }
}