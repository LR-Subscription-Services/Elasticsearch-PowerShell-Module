Function Invoke-RunUserCommand {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object] $Stage,

        [Parameter(Mandatory = $true, Position = 1)]
        [object] $Nodes
    )
    ForEach ($Node in $Nodes) {
        if ($Stage.UserCommands) {
            $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr)
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField2 "Node: $($Node.hostname)" -logMessage "Begin Step"
            ForEach ($UserCommand in $Stage.UserCommands) {
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logMessage "Command: $($UserCommand)"
                $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {bash -c $UserCommand} -ErrorAction SilentlyContinue
            }
            New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField2 "Node: $($Node.hostname)" -logMessage "End Step"
        }
    }
}