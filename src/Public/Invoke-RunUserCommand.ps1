Function Invoke-RunUserCommand {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object] $Stage,

        [Parameter(Mandatory = $true, Position = 1)]
        [object] $Nodes,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $SSHKeyPath
    )
    Begin {}

    Process {
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logMessage "Begin Step"
        ForEach ($Node in $Nodes) {
            if ($Stage.UserCommands) {
                $CmdCount = 1
                $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr) -Path $SSHKeyPath
                ForEach ($UserCommand in $Stage.UserCommands) {
                    switch ($Usercommand.Type) {
                        'bash' {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logExField2 "Type: Bash" -logMessage "Command: $($UserCommand.Command)"
                            Try {
                                $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {& $args[0] $args[1] $args[2]} -ArgumentList 'bash', '-c', $UserCommand.Command -ErrorAction SilentlyContinue
                            } Catch {
                                write-host $_
                            }
                        }
                        'pwsh' {
                            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logExField2 "Type: Pwsh" -logMessage "Command: $($UserCommand.Command)"
                            try {
                                $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {& $args[0]} -ArgumentList $UserCommand.Command -ErrorAction SilentlyContinue
                            } Catch {
                                write-host $_
                            }
                        }
                        default {
                            New-ProcessLog -logSev e -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logExField2 "Type: Error" -logMessage "Command type error.  Submitted type: $($UserCommand.Type)"
                        }
                    }
                    $HostResult
                    $CmdCount += 1
                }
            } else {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logMessage "No user commands defined."
            }
        }
        New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logMessage "End Step"
    }
}