Function New-ProcessLog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('e', 's', 'a', 'i', 'd', 'w', ignorecase=$true)]
        [string] $logSev,


        [Parameter(Mandatory = $true, Position = 1)]
        [string] $logStage,


        [Parameter(Mandatory = $false, Position = 2)]
        [string] $logStep,


        [Parameter(Mandatory = $false, Position = 3)]
        [string] $esHealth,


        [Parameter(Mandatory = $true, Position = 4)]
        [string] $logMessage,


        [Parameter(Mandatory = $false, Position = 5)]
        [string] $logExField1,


        [Parameter(Mandatory = $false, Position = 6)]
        [string] $logExField2,


        [Parameter(Mandatory = $false, Position = 7)]
        $LogFile,


        [Parameter(Mandatory = $false, Position = 8)]
        [string] $WebhookDest,

        
        [Parameter(Mandatory = $false, Position = 9)]
        [switch] $SendWebhook,


        [Parameter(Mandatory = $false, Position = 9)]
        [switch] $PassThru
    )
    Begin {
        $TC = (Get-Culture).TextInfo
    }
   
    Process {
        $cTime = "{0:MM/dd/yy} {0:HH:mm:ss}" -f (Get-Date)

        Switch ($logSev) {
            e {$_logSev = 'ERROR  '}
            s {$_logSev = 'STATUS '}
            w {$_logSev = 'WARNING'}
            a {$_logSev = 'ALERT  '}
            i {$_logSev = 'INFO   '}
            d {$_logSev = 'DEBUG  '}
            default {$logSev = "LOGGER ERROR"}
        }

        # Retrieve cluster health at each logging instance
        if ($esHealth) {
            $ClusterStatus = $($TC.ToTitleCase($esHealth))
        } else {
            $ClusterHealth = Get-EsClusterHealth
            $ClusterStatus = $($TC.ToTitleCase($($ClusterHealth.status)))
        }

        $LogObj = [PSCustomObject]@{
            timestamp = $cTime
            severity = $_logSev
            health = $ClusterStatus
            stage = $logStage
            step = $LogStep
            message = $logMessage
        }
        $LogOutput = "$($LogObj.timestamp) | $($LogObj.severity) | Health: $($LogObj.health) | Stage: $($LogObj.stage) | Step: $($LogObj.step) | "

        if ($logExField1) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_01 -Value $logExField1 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_01) | "
        }

        if ($logExField2) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_02 -Value $logExField1 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_02) | "
        }

        if ($WebhookDest -and $SendWebhook) {
            Invoke-RestMethod -Method 'Post' -Uri $WebhookDest -Body $($LogObj | ConvertTo-Json -Compress -Depth 3)
        }

        $LogOutput = $LogOutput + "$($LogObj.message)"
        
        return $LogOutput
    }
}

