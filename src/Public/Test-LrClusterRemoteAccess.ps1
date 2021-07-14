using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Test-LrClusterRemoteAccess {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string[]] $HostNames,

        [string] $UserName = 'logrhythm',

        [string] $KeyFilePath = '~/.ssh/id_rsa'
    )
    Begin {
        # Establish existing PS Sessions
        $CurrentPSSessions = Get-PSSession
    }
    
    Process {
        # Cleanup Broken PS Sessions
        ForEach ($CPSSession in $CurrentPSSessions) {
            if ($CPSSession.State -like "Broken") {
                Remove-PSSession -Session $CPSSession
            }
        }
        # Refresh active Ps Sessions
        $CurrentPSSessions = Get-PSSession

        $Results = [List[object]]::new()
        ForEach ($hostname in $hostnames) {
            if ($CurrentPSSessions.ComputerName -notcontains $hostname) {
                try {
                    $PSSession = New-PSSession -HostName $hostname -UserName $UserName -KeyFilePath $KeyFilePath -ErrorAction Stop
                    $Results.add($PSSession)
                } Catch {
                    $ConnectionResults = $(Test-Connection -IPv4 $HostName -Quiet)
                    if ($ConnectionResults) {
                        $Availability = "Available"
                    } else {
                        $Availability = "None"
                    }
                    $Result = [PSCustomObject]@{
                        Id = -1
                        Name = "Error"
                        Transport = "SSH"
                        ComputerName = $hostname
                        ComputerType = "RemoteMachine"
                        State = "Error"
                        ConfigurationName = "DefaultShell"
                        Availability = $Availability
                        Error = $_
                    }
                    $Results.add($Result)
                }
            } else {
                $Results.Add($($CurrentPSSessions | Where-Object -Property 'ComputerName' -eq $hostname))
            }

            Start-Sleep 0.2
        }

        return $Results
    }
}