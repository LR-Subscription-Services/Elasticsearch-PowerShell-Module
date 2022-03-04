
# Good command: Get-EsIndex | Where-Object -Property status -like "open" | Sort-Object -Property index | Format-table
# 5060699
$Indices = Get-EsIndex
ForEach ($Index in $Indices[0..1]) {
    $IndexSettings = Get-EsIndexSettings -Index $Index.Index
    Write-Host "Index: $($Index.Index) Status: $($Index.status) UUID: $($Index.uuid) Version: $($IndexSettings.version.created) Type: $($IndexSettings.routing.allocation.require.box_type)  Replicas: $($IndexSettings.number_of_replicas)"
    if (($($IndexSettings.version.created) -eq 6081599) -and ($IndexSettings.routing.allocation.require.box_type -like 'warm') -and ($IndexSettings.number_of_replicas -eq 0)) {
        Open-EsIndex -Index $($Index.Index)
        Invoke-MonitorEsInit 
        Update-EsIndexReplicas -Index $($Index.Index) -Replicas 1
        Invoke-MonitorEsInit
        Update-EsIndexReplicas -Index $($Index.Index) -Replicas 0
        Close-EsIndex -Index $($Index.Index)
    }
}