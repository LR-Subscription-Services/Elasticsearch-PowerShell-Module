function Split-ArraySegments {
    <#
    .SYNOPSIS
        Breaks an array into a segments of smaller arrays.
    .DESCRIPTION
        Allows the segmentation of arrays with efficiency.
    .PARAMETER Array
    .PARAMETER Segments
    .INPUTS
    .OUTPUTS
        Array of arrays broken into segments based on Segments variable.
    .EXAMPLE
    .NOTES
        LogRhythm.Tools
    .LINK
        https://github.com/LogRhythm-Tools/LogRhythm.Tools
    #> 
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNull()]
        [object[]]$InputArray,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [int32] $Segments
    )
    Begin {
        $ArrayList = New-Object System.Collections.ArrayList
        $Count = 0 

        if ($Segments -le 0) {
            $Segments = 1
        }
    }
    
    Process {
        # Establish ArrayList Objects 
        0..($Segments-1) | ForEach-Object {
            [void]$ArrayList.Add((New-Object System.Collections.ArrayList))
        }

        # Populate ArrayLists
        foreach($Entry in $InputArray) {
        [void]$ArrayList[$Count % $Segments].Add($Entry) 
        $Count++ 
        }

        return ,$ArrayList.ToArray()
    }
}