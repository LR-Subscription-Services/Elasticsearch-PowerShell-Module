Function Invoke-CollectEsMetrics {
    [CmdletBinding()]
    Param(
        [int] $Interval = 60
    )
    Begin {
        $Run = $true
        $nextRun = $(get-date).AddSeconds($Interval)
    }

    Process {
       do {
            if ($(get-date) -ge $nextRun) {
                # $Timer = [System.Diagnostics.Stopwatch]::StartNew()
                $indexDate = [DateTime]::UtcNow.ToString("yyyy.MM.dd")
                $Response = Get-EsClusterHealth
                $ClusterName = $Response.cluster_name
                $Response | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
                switch ($Response.status) {
                    'green' {$Response | add-member -Name "status_code" -Value 0 -MemberType NoteProperty}
                    'yellow' {$Response | add-member -Name "status_code" -Value 1 -MemberType NoteProperty}
                    'red' {$Response | add-member -Name "status_code" -Value 2 -MemberType NoteProperty}
                }
                Send-EsMessage -Index "elasticsearch_prod_metrics-$($indexDate)" -Body $Response

                $Response = Get-EsStats -Mode 'cluster'
                $Response | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
                Send-EsMessage -Index "elasticsearch_prod_metrics-$($indexDate)" -Body $Response

                $Response = Get-EsStats -Mode 'nodes'
                ForEach ($Node in $Response.nodes) {
                    $Node | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty -Force
                    $Node | add-member -Name "cluster_name" -Value $ClusterName -MemberType NoteProperty -Force
                    $Node | add-member -Name "node_id" -Value $Node.id -MemberType NoteProperty -Force
                    $Node.PSObject.properties.remove('id')
                    $res = Send-EsMessage -Index "elasticsearch_prod_metrics-$($indexDate)" -Body $Node -PassThru
                }

                $Response = Get-EsStats
                $Response._all | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty -Force
                $Response._all | add-member -Name "cluster_name" -Value $ClusterName -MemberType NoteProperty -Force
                $res = Send-EsMessage -Index "elasticsearch_prod_metrics-$($indexDate)" -Body $Response._all -Passthru


                $TimeDiff = New-TimeSpan -Start $(get-date) -End $nextRun
            }

            if ([int]$TimeDiff.TotalSeconds -le 0) {} else {
                Write-Output "Sleeping $($TimeDiff.TotalSeconds)s"
                Start-Sleep $($TimeDiff.TotalSeconds)
                $nextRun = $(get-date).AddSeconds($Interval)
            }
            $TimeDiff = 0
        } while ($Run)
    }


    End {

    }
}