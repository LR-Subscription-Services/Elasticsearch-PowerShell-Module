Function Invoke-SelectionPrompt {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, Position = 0)]
        [string] $Title,

        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Question,

        [Parameter(Mandatory = $false, Position = 1)]
        [string] $Type = "YN"
    )
    Begin {
        $Choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    }
    
    Process {
        Switch ($Type) {
            YN {
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                break
            }
            default {
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $Choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                break
            }
        }
        $UserDecision = $Host.UI.PromptForChoice($Title, $Question, $Choices, 1)

        return $UserDecision 
    }
}

