Function Add-LrHostSSHConfig {
    [CmdletBinding()]
    Param(
        [string] $Path
    )
    Begin {
        $Config = 'Host *
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        LogLevel QUIET
        ServerAliveInterval 300
        ServerAliveCountMax 2'
    }
    
    Process {
        $Output = [PSCustomObject]@{
            Status = $false
            Action = $false
        }
        if ($(Test-Path -Path $Path)) {
            write-host "SSH Configuration Policy has previously been set."
            $ConfigContent = Get-Content -Path $Path

            if ($Config -eq $ConfigContent) {
                write-host "SSH Configuration Policy is equal to required config."
                $Output.Status = $true
                $Output.Action = 'none'
            } else {
                write-host "SSH Configuration Policy has previously been set but not equal to required config."
                try {
                    move-item -Path $Path -Destination $($Path+".bak") -Force
                } Catch {
                    write-host "Unable to establish backup copy of existing config."
                } 
                try {
                    $Config | out-file -FilePath $Path
                    write-host "SSH Configuration Policy has been set."
                    $Output.Status = $true
                    $Output.Action = 'revert'
                } catch {
                    write-host "SSH Configuration Policy has not been set."
                }
                
            }
        } else {
            write-host "SSH Configuration Policy does not exist."
            try {
                $Config | out-file -FilePath $Path
                write-host "SSH Configuration Policy has been set."
                $Output.Status = $true
                $Output.Action = 'remove'
            } catch {
                write-host "SSH Configuration Policy has not been set."
            }
        }
        Invoke-Command -ScriptBlock {bash -c "chmod 600 $Path"}
        return $Output 
    }
}