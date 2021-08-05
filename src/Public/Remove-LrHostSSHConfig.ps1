Function Remove-LrHostSSHConfig {
    [CmdletBinding()]
    Param(
        [string] $Path,

        [string] $Action
    )
    Begin {

    }
    
    Process {
        switch ($Action) {
            none {break}
            remove {
                remove-item -Path $Path -Force
            }
            revert {
                remove-item -Path $Path 
                move-item -Path $Path+".bak" -Destination $Path -Force
                bash -c "chmod 600 $Path"
            }
            default {remove-item -Path $Path -Force}
        }
    }
}