Function Post-EsMetrics {
    [CmdletBinding()]
    Param(

    )
    Begin {
        $Headers = [Dictionary[string,string]]::new()
        $Headers.Add("Content-Type","application/json")

        $Method = "Post"

        $BaseUrl = "http://localhost:9200"
    }

    Process {
       
        $Response = Get-EsClusterHealth
        $ClusterName = $Response.cluster_name
        $Response | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        switch ($Response.status) {
            'green' {$Response | add-member -Name "status_code" -Value 0 -MemberType NoteProperty}
            'yellow' {$Response | add-member -Name "status_code" -Value 1 -MemberType NoteProperty}
            'red' {$Response | add-member -Name "status_code" -Value 2 -MemberType NoteProperty}
        }
        Send-EsMessage -Index 'elasticsearch_prod_metrics' -Body $($Response | ConvertTo-Json -Depth 7 -Compress)

        $Response = Get-EsStats -Mode 'cluster'
        $Response | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        Send-EsMessage -Index 'elasticsearch_prod_metrics' -Body $($Response | ConvertTo-Json -Depth 7 -Compress)

        $Response = Get-EsNodes -Mode 'nodes'
        ForEach ($Node in $Response.nodes) {
            $Node | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty -Force
            $Node | add-member -Name "cluster_name" -Value $ClusterName -MemberType NoteProperty -Force
            Send-EsMessage -Index 'elasticsearch_prod_metrics' -Body $($Node | ConvertTo-Json -Depth 7 -Compress)
        }
    }

    End {

    }
}