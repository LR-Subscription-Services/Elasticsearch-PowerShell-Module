using namespace System
using namespace System.IO
using namespace System.Collections.Generic
Function Send-LrSdpWebhook {
    <#
    .SYNOPSIS
        Submits a log message in to a LogRhythm Open Collector Webhook Beat for log ingestion.
    .DESCRIPTION
        This cmdlet enables submitting logs to LogRhythm's Webhook Beat with user defined JSON or submitted with
        the Source Defined Parser augmentation applied.

        Formats submitted data elements based on PowerShell Paramaters based on LogRhythm metadata schema.
    .PARAMETER JsBody

    .PARAMETER RBP
        Intiger value applied as a new value for the Alarm's Risk Based Priority score.

        If not provided the RBP will remain unchanged.

        Valid range: 0-100
    .PARAMETER PassThru
        Switch paramater that will enable the return of the output object from the cmdlet.
    .PARAMETER Credential
        PSCredential containing an API Token in the Password field.
    .INPUTS
        [System.Int]          -> AlarmId
        [System.String]       -> AlarmStatus
        [System.Int]          -> RBP
        [System.Switch]       -> PassThru
        [PSCredential]        -> Credential
    .OUTPUTS
        By defaul the output is null unless an error is generated.
        
        With the PassThru switch a PSCustomObject representing LogRhythm Alarms and their contents.
    .EXAMPLE
        PS C:\> Update-LrAlarm -AlarmId 185 -AlarmStatus New
         
    .EXAMPLE
        PS C:\> Update-LrAlarm -AlarmId 185 -AlarmStatus opened -RBP 35
        
    .EXAMPLE
        PS C:\> Update-LrAlarm -AlarmId 185 -AlarmStatus New -PassThru 

        statusCode statusMessage responseMessage
        ---------- ------------- ---------------
            200 OK            Success
    .EXAMPLE
        PS C:\> Update-LrAlarm -AlarmId 185 -AlarmStatus opened -RBP 35 -PassThru

        statusCode statusMessage responseMessage
        ---------- ------------- ---------------
            200 OK            Success
    .NOTES
        LogRhythm-API        
    .LINK
        https://github.com/LogRhythm-Tools/LogRhythm.Tools
        account
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false, Position = 0)]
        [String] $Account,


        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Action,


        [Parameter(Mandatory = $false, Position = 2)]
        [Int32] $Amount,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $Command,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $Cve,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dinterface,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dip,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dmac,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dname,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dnatip,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $dnatport,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $domainimpacted,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $domainorigin,


        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $dport,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $group,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $hash,


        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $kilobytes,


        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $kilobytesin,


        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $kilobytesout,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $login,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $milliseconds,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $minutes,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $object,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $objectname,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $objecttype,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $packetsin,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $packetsout,
       
        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $parentprocessid,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $parentprocessname,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $parentprocesspath,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [String] $policy,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $process,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $processid,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [string] $protname,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $protnum,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $quantity,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $rate,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $reason,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $recipient,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $responsecode,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $result,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $seconds,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $sender,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $serialnumber,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $session,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $sessiontype,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $severity,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $sinterface,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $sip,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $size,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $smac,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $sname,


        [Parameter(Mandatory = $false, Position = 3)]
        [String] $snatip,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $snatport,

        [Parameter(Mandatory = $false, Position = 3)]
        [int32] $sport,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $status,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $subject,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag1,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag2,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag3,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag4,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag5,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag6,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag7,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag8,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag9,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $tag10,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $threatid,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $threatname,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $time,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $url,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $useragent,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $vendorinfo,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $version,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $vmid,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $fqbn,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $original_message,

        [Parameter(Mandatory = $false, Position = 0)]
        [String] $OCUrl
    )

    Begin {
        # Request Setup
        if ($OCUrl) {
            $BaseUrl = $OCUrl
        } else {
            $BaseUrl = $LrtConfig.OC.BaseUrl
        }
        

        # Define HTTP Headers
        $Headers = [Dictionary[string,string]]::new()
        $Headers.Add("Content-Type","application/json")

        # Define HTTP Method
        $Method = $HttpMethod.post

        # Check preference requirements for self-signed certificates and set enforcement for Tls1.2 
        Enable-TrustAllCertsPolicy
    }

    Process {
        $ErrorObject = [PSCustomObject]@{
            Code                  =   $null
            Error                 =   $false
            Type                  =   $null
            Note                  =   $null
            Raw                   =   $null
        }

        $OCLog = [PSCustomObject]@{
            whsdp = $true
        }

        if ($Account) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'account' -Value $Account -Force
        }
        
        if ($Action) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'action' -Value $Action -Force
        }

        if ($Amount) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'amount' -Value $Amount -Force
        }

        if ($Command) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'command' -Value $Command -Force
        }

        if ($Cve) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'cve' -Value $Cve -Force
        }

        if ($dinterface) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dinterface' -Value $dinterface -Force
        }

        if ($dip) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dip' -Value $dip -Force
        }

        if ($dmac) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dmac' -Value $dmac -Force
        }

        if ($dname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dname' -Value $dname -Force
        }

        if ($dnatip) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dnatip' -Value $dnatip -Force
        }

        if ($dnatport) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'dnatport' -Value $dnatport -Force
        }
        if ($domainimpacted) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'domainimpacted' -Value $domainimpacted -Force
        }
        if ($domainorigin) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'domainorigin' -Value $domainorigin -Force
        }
        if ($group) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'group' -Value $group -Force
        }
        if ($hash) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'hash' -Value $hash -Force
        }
        if ($kilobytes) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'kilobytes' -Value $kilobytes -Force
        }
        if ($kilobytesin) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'kilobytesin' -Value $kilobytesin -Force
        }
        if ($kilobytesout) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'kilobytesout' -Value $kilobytesout -Force
        }
        if ($login) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'login' -Value $login -Force
        }
        if ($milliseconds) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'milliseconds' -Value $milliseconds -Force
        }
        if ($minutes) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'minutes' -Value $minutes -Force
        }


        if ($object) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'object' -Value $object -Force
        }
        if ($objectname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'objectname' -Value $objectname -Force
        }
        if ($objecttype) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'objecttype' -Value $objecttype -Force
        }
        if ($packetsin) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'packetsin' -Value $packetsin -Force
        }
        if ($packetsout) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'packetsout' -Value $packetsout -Force
        }
        if ($parentprocessid) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'parentprocessid' -Value $parentprocessid -Force
        }
        if ($parentprocessname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'parentprocessname' -Value $parentprocessname -Force
        }
        if ($parentprocesspath) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'parentprocesspath' -Value $parentprocesspath -Force
        }
        
        if ($policy) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'policy' -Value $policy -Force
        }
        if ($process) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'process' -Value $process -Force
        }
        if ($processid) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'processid' -Value $processid -Force
        }
        if ($protname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'protname' -Value $protname -Force
        }
        if ($protnum) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'protnum' -Value $protnum -Force
        }
        if ($quantity) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'quantity' -Value $quantity -Force
        }
        if ($rate) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'rate' -Value $rate -Force
        }
        if ($reason) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'reason' -Value $reason -Force
        }
        if ($recipient) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'recipient' -Value $recipient -Force
        }
        if ($responsecode) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'responsecode' -Value $responsecode -Force
        }


        if ($result) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'result' -Value $result -Force
        }
        if ($seconds) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'seconds' -Value $seconds -Force
        }
        if ($sender) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sender' -Value $sender -Force
        }
        if ($serialnumber) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'serialnumber' -Value $serialnumber -Force
        }
        if ($session) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'session' -Value $session -Force
        }
        if ($sessiontype) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sessiontype' -Value $sessiontype -Force
        }
        if ($severity) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'severity' -Value $severity -Force
        }
        if ($sinterface) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sinterface' -Value $sinterface -Force
        }
        if ($sip) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sip' -Value $sip -Force
        }
        if ($size) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'size' -Value $size -Force
        }
        if ($smac) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'smac' -Value $smac -Force
        }
        if ($sname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sname' -Value $sname -Force
        }

        if ($snatip) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'snatip' -Value $snatip -Force
        }
        if ($snatport) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'snatport' -Value $snatport -Force
        }
        if ($sport) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'sport' -Value $sport -Force
        }
        if ($status) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'status' -Value $status -Force
        }
        if ($subject) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'subject' -Value $subject -Force
        }
        if ($tag1) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag1' -Value $tag1 -Force
        }
        if ($tag2) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag2' -Value $tag2 -Force
        }
        if ($tag3) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag3' -Value $tag3 -Force
        }
        if ($tag4) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag4' -Value $tag4 -Force
        }
        if ($tag5) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag5' -Value $tag5 -Force
        }
        if ($tag6) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag6' -Value $tag6 -Force
        }
        if ($tag7) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag7' -Value $tag7 -Force
        }
        if ($tag8) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag8' -Value $tag8 -Force
        }
        if ($tag9) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag9' -Value $tag9 -Force
        }
        if ($tag10) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'tag10' -Value $tag10 -Force
        }
        if ($threatid) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'threatid' -Value $threatid -Force
        }
        if ($threatname) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'threatname' -Value $threatname -Force
        }
        if ($timestamp8601) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'timestamp.iso8601' -Value $timestamp8601 -Force
        }
        if ($timestampepoch) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'timestamp.epoch' -Value $timestampepoch -Force
        }
        if ($url) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'url' -Value $url -Force
        }
        if ($useragent) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'useragent' -Value $useragent -Force
        }
        if ($vendorinfo) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'vendorinfo' -Value $vendorinfo -Force
        }
        if ($version) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'version' -Value $version -Force
        }
        if ($vmid) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'vmid' -Value $vmid -Force
        }

        if ($fqbn) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'fullyqualifiedbeatname' -Value $fqbn -Force
        }
        if ($original_message) {
            $OCLog | Add-Member -MemberType NoteProperty -Name 'original_message' -Value $original_message -Force
        }


        # Establish Body Contents
        $Body = $OCLog | ConvertTo-Json


        $RequestUrl = $BaseUrl

        # Send Request
        try {
            $Response = Invoke-RestMethod $RequestUrl -Headers $Headers -Method $Method -Body $Body
        } catch [System.Net.WebException] {
            $Err = Get-RestErrorMessage $_
            $ErrorObject.Error = $true
            $ErrorObject.Type = "System.Net.WebException"
            $ErrorObject.Code = $($Err.statusCode)
            $ErrorObject.Note = $($Err.message)
            $ErrorObject.Raw = $_
            return $ErrorObject
        }

        if ($PassThru) {
            if ($Response.alarmDetails) {
                return $Response.alarmDetails
            } else {
                return $Response
            }
        }
    }

    End {
    }
}