Function Invoke-RunUserCommand {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]] $Commands,

        [Parameter(Mandatory = $true, Position = 1)]
        [object] $Nodes
    )
    Begin {}

    Process {
        ForEach ($Node in $Nodes) {
            if ($Commands) {
                $NodeSession = Test-LrClusterRemoteAccess -Hostnames $($Node.ipaddr)
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField2 "Node: $($Node.hostname)" -logMessage "Begin Step"
                $CmdCount = 1
                ForEach ($UserCommand in $Commands) {
                    New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField1 "Node: $($Node.hostname)" -logExField2 "Command Number: $($CmdCount)" -logMessage "Command: $($UserCommand)"
                    Try {
                        $HostResult = Invoke-Command -Session $NodeSession -ScriptBlock {bash -c $UserCommand} -ErrorAction SilentlyContinue
                    } Catch {
                        write-host $_
                    }
                    $CmdCount += 1
                }
                New-ProcessLog -logSev i -logStage $($Stage.Name) -logStep 'Run User Command' -logExField2 "Node: $($Node.hostname)" -logMessage "End Step"
            }
        }
    }
}