#region: Module Info                                                                     
# Module Name: To make it easier to change the name of the module.
# NOTE: These two variables should be set exactly the same as they appear in setup\New-LrtConfig!
#       The name of the file may be $ModuleName.config.json, but the object is still called
$ModuleName = "ElasticSearch.Module"

# [Namespaces]: Directories to include in this module
$Namespaces = @(
    "Public",
    "Private"
)
#endregion

#region: Import Functions                                                                
# Build Import Hash Table
$Includes = @{}
foreach ($namespace in $Namespaces) {
    $Includes.Add($namespace, @(Get-ChildItem -Recurse -Include *.ps1 -Path $PSScriptRoot\$namespace -ErrorAction SilentlyContinue))
}
# Run Import
foreach ($include in $Includes.GetEnumerator()) {
    foreach ($file in $include.Value) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error "  - Failed to import function $($file.BaseName): $_"
        }
    }
}
#endregion

#region: Export Module Members  
Export-ModuleMember -Variable ModuleName
Export-ModuleMember -Function $Includes["Public"].BaseName
#endregion