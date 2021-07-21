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


        [Parameter(Mandatory = $true, Position = 3)]
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
        [switch] $PassThru
    )
    Begin {
        
    }
   
    Process {
        $cTime = "{0:MM/dd/yy} {0:HH:mm:ss}" -f (Get-Date)

        Switch ($logSev) {
            e {$_logSev = 'ERROR'}
            s {$_logSev = 'STATUS'}
            w {$_logSev = 'WARNING'}
            a {$_logSev = 'ALERT'}
            i {$_logSev = 'INFO'}
            d {$_logSev = 'DEBUG'}
            default {$logSev = "LOGGER ERROR"}
        }

        $LogObj = [PSCustomObject]@{
            timestamp = $cTime
            severity = $_logSev
            health = $esHealth
            stage = $logStage
            step = $LogStep
            message = $logMessage
        }
        $LogOutput = "$($LogObj.timestamp) | $($LogObj.severity) | Stage: $($LogObj.stage) | Health: $($LogObj.health) | Step: $($LogObj.step) | "

        if ($logExField1) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_01 -Value $logExField1 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_01) | "
        }

        if ($logExField2) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_02 -Value $logExField1 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_02) | "
        }

        $LogOutput = $LogOutput + "$($LogObj.message)"
        
        return $LogOutput
    }
}

