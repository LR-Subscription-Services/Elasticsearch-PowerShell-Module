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

        [Parameter(Mandatory = $false, Position = 4)]
        [string] $Node,

        [Parameter(Mandatory = $false, Position = 5)]
        [string] $Index,

        [Parameter(Mandatory = $true, Position = 6)]
        [string] $logMessage,


        [Parameter(Mandatory = $false, Position = 7)]
        [string] $logExField1,


        [Parameter(Mandatory = $false, Position = 8)]
        [string] $logExField2,


        [Parameter(Mandatory = $false, Position = 9)]
        $LogFile,


        [Parameter(Mandatory = $false, Position = 10)]
        [string] $WebhookDest,

        
        [Parameter(Mandatory = $false, Position = 11)]
        [switch] $SendWebhook,


        [Parameter(Mandatory = $false, Position = 12)]
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

        Switch ($($LogObj.health)) {
            "green"  {$_logHealth = 'Green '}
            "yellow" {$_logHealth = 'Yellow'}
            "red"    {$_logHealth = 'Red   '}
            default {$_logHealth = $($LogObj.health)}
        }

        Switch ($($LogObj.stage)) {
            "Check"    {$_logStage = 'Check   '}
            "Init"     {$_logStage = 'Init    '}
            "Running"  {$_logStage = 'Running '}
            "Verify"   {$_logStage = 'Verify  '}
            "Complete" {$_logStage = 'Complete'}
            default {$_logStage = $($LogObj.stage)}
        }

        $LogOutput = "$($LogObj.timestamp) | $($LogObj.severity) | Health: $_logHealth | Stage: $_logStage | Step: $($LogObj.step) | "

        if ($Node) {
            $LogObj | Add-Member -MemberType NoteProperty -Name node -Value $Node -Force
            $LogOutput = $LogOutput + "Node: $($Node) | "
        }

        if ($Index) {
            $LogObj | Add-Member -MemberType NoteProperty -Name index -Value $Index -Force
            if ($Index -like "emdb_*") {
                switch -Regex ($Index) {
                    "emdb_location_.*" {$_index = "emdb_location  "}
                    "emdb_list.*" {$_index = "emdb_list_items"}
                    "emdb_ad_groups_.*" {$_index = "emdb_ad_groups "}
                    "emdb_acl_msg_source_.*" {$_index= "emdb_acl_msgsrc"}
                    default {$_index = $Index}
                }
            } else {
                $_index = $Index
            }
            $LogOutput = $LogOutput + "Index: $($_index) | "
        }

        if ($logExField1) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_01 -Value $logExField1 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_01) | "
        }

        if ($logExField2) {
            $LogObj | Add-Member -MemberType NoteProperty -Name step_note_02 -Value $logExField2 -Force
            $LogOutput = $LogOutput + "$($LogObj.step_note_02) | "
        }

        if ($WebhookDest -and $SendWebhook) {
            Invoke-RestMethod -Method 'Post' -Uri $WebhookDest -Body $($LogObj | ConvertTo-Json -Compress -Depth 3)
        }

        $LogOutput = $LogOutput + "$($LogObj.message)"
        
        return $LogOutput
    }
}

