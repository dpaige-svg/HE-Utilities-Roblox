# Synchronize additive Phase 4/5 sources, preserving all other model text.
$ErrorActionPreference = 'Stop'
$modelPath = Join-Path $PSScriptRoot 'HE-Utilties v0.3.rbxmx'
$modelText = [IO.File]::ReadAllText($modelPath)
$document = [xml]$modelText
$updates = @{
    AutoScanService = 'Scanner'
    DetectionReporter = 'Scanner'
    AutoScanServiceTest = 'Tests'
    NotificationBatch = 'UI'
    MonitorController = 'UI'
    MonitorWidget = 'UI'
    MonitorUITest = 'Tests'
    PluginMain = ''
    FindingNavigator = 'Actions'
    FindingNavigatorTest = 'Tests'
    ObjectScanner = 'Scanner'
    ObjectScannerTest = 'Tests'
}
foreach ($name in $updates.Keys) {
    $folder = $updates[$name]
    $sourcePath = if ($name -eq 'PluginMain') { 'HE-Utilties v0.3/PluginMain.server.lua' } else { "HE-Utilties v0.3/$folder/$name.lua" }
    $class = if ($name -eq 'PluginMain') { 'Script' } else { 'ModuleScript' }
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $sourcePath))
    if ($source.Contains(']]>')) { throw 'Source contains an unsupported CDATA terminator' }
    $existing = $document.SelectSingleNode("//Item[Properties/string[@name='Name']='$name']")
    if ($existing) {
        $referent = [regex]::Escape($existing.GetAttribute('referent'))
        $pattern = '(?s)(<Item class="' + $class + '" referent="' + $referent + '">\s*<Properties>.*?<ProtectedString name="Source">).*?(</ProtectedString>)'
        $replacement = '<![CDATA[' + $source + ']]>'
        $modelText = [regex]::Replace($modelText, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + $replacement + $match.Groups[2].Value })
    } else {
        $parent = if ($folder) { $document.SelectSingleNode("//Item[Properties/string[@name='Name']='$folder']") } else { $document.SelectSingleNode('/roblox/Item') }
        $referent = [regex]::Escape($parent.GetAttribute('referent'))
        $pattern = '(?s)(<Item class="Folder" referent="' + $referent + '">\s*<Properties>.*?</Properties>)'
        $addition = "`n<Item class=`"$class`" referent=`"RBX$([guid]::NewGuid().ToString('N').ToUpper())`"><Properties><string name=`"Name`">$name</string><ProtectedString name=`"Source`"><![CDATA[$source]]></ProtectedString></Properties></Item>"
        $modelText = [regex]::Replace($modelText, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + $addition })
    }
}
$updated = [xml]$modelText
foreach ($old in $document.SelectNodes('//Item[Properties/ProtectedString[@name="Source"]]')) {
    $name = $old.SelectSingleNode('Properties/string[@name="Name"]').InnerText
    if ($updates.ContainsKey($name)) { continue }
    $node = $updated.SelectSingleNode("//Item[@referent='$($old.GetAttribute('referent'))']/Properties/ProtectedString[@name='Source']")
    if ($node.InnerText -cne $old.Properties.ProtectedString.InnerText) { throw "Unexpected source change: $name" }
}
foreach ($name in $updates.Keys) {
    $node = $updated.SelectSingleNode("//Item[Properties/string[@name='Name']='$name']/Properties/ProtectedString[@name='Source']")
    $sourcePath = if ($name -eq 'PluginMain') { 'HE-Utilties v0.3/PluginMain.server.lua' } else { "HE-Utilties v0.3/$($updates[$name])/$name.lua" }
    $expected = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $sourcePath))
    if ($node.InnerText -cne $expected) { throw "Model synchronization failed: $name" }
}
[IO.File]::WriteAllText($modelPath, $modelText)
Write-Output 'Phase 4/5 modules synchronized; other module sources preserved.'

# Distributable plugin: exclude executable test runners from startup.
$pluginDocument = [xml]$modelText
$pluginRoot = $pluginDocument.SelectSingleNode('/roblox/Item')
$pluginRoot.SelectSingleNode('Properties/string[@name="Name"]').InnerText = 'HE-Utilties v0.3'
foreach ($item in @($pluginRoot.SelectNodes('Item[@class="Script"]'))) {
    if ($item.SelectSingleNode('Properties/string[@name="Name"]').InnerText -ne 'PluginMain') {
        [void]$pluginRoot.RemoveChild($item)
    }
}
$pluginDocument.Save((Join-Path $PSScriptRoot 'HE-Utilties v0.3.rbxmx'))
Write-Output 'HE-Utilties v0.3.rbxmx packaged without automatic test runners.'
