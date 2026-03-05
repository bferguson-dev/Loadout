# test-custom-app.ps1 -- Functional tests for Session 15 Custom App feature
# Tests the embedded dialog XAML, Search-WingetApps parser, and Save-UserManifest
# without launching the WPF window.
#
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File tests/test-custom-app.ps1

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP = [System.IO.Path]::GetTempPath()
}
if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    $env:APPDATA = Join-Path $env:TEMP 'Loadout-AppData'
    if (-not (Test-Path $env:APPDATA)) {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    }
}
$repoRoot   = Split-Path $PSScriptRoot -Parent
$loadoutPs1 = Join-Path $repoRoot 'src/Loadout.ps1'

$pass = 0
$fail = 0

function Assert {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  PASS  $Label"
        $script:pass++
    } else {
        Write-Host "  FAIL  $Label"
        $script:fail++
    }
}

$content = Get-Content $loadoutPs1 -Raw

# Parse the AST once for function extraction
$tokens  = $null
$errors  = $null
$ast     = [System.Management.Automation.Language.Parser]::ParseInput(
               $content, [ref]$tokens, [ref]$errors)

# -----------------------------------------------------------------------
# 1. Embedded dialog XAML -- extract and validate as XML
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Show-CustomAppDialog embedded XAML ---'

$dialogXaml = $null
$allHereStrings = [regex]::Matches($content, "(?s)@'(.+?)'@")
foreach ($m in $allHereStrings) {
    $candidate = $m.Groups[1].Value.Trim()
    if ($candidate -match 'Add Custom App') {
        $dialogXaml = $candidate
        break
    }
}

Assert ($null -ne $dialogXaml) 'Dialog XAML here-string found in Loadout.ps1'

if ($null -ne $dialogXaml) {
    $xmlValid = $false
    try {
        $xml = [System.Xml.XmlDocument]::new()
        $xml.LoadXml($dialogXaml)
        $xmlValid = $true
    } catch {
        Write-Host "  XML parse error: $_"
    }
    Assert $xmlValid 'Dialog XAML parses as valid XML'

    # Required controls
    $requiredControls = @(
        'TxtDisplayName', 'TxtDescription', 'CmbCategory', 'CmbMethod',
        'LblPrimaryId', 'TxtPrimaryId', 'PnlWingetSearch', 'TxtSearch',
        'BtnSearchWinget', 'PnlSearchResults', 'LstSearchResults',
        'PnlSilentArgs', 'TxtSilentArgs', 'BtnSaveApp', 'BtnCancelApp'
    )
    foreach ($ctrl in $requiredControls) {
        Assert ($dialogXaml -match "x:Name=""$ctrl""") "x:Name=""$ctrl"" present in dialog XAML"
    }
}

# -----------------------------------------------------------------------
# 2. FindName() calls vs x:Name declarations -- no orphaned FindName calls
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- FindName() vs x:Name cross-check ---'

$funcDef = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Show-CustomAppDialog'
}, $true)

Assert ($null -ne $funcDef) 'Show-CustomAppDialog AST node found'

if ($null -ne $funcDef -and $null -ne $dialogXaml) {
    $funcBody   = $funcDef.Extent.Text
    $findNames  = [regex]::Matches($funcBody, "FindName\('([^']+)'\)")
    Assert ($findNames.Count -gt 0) "FindName() calls found in Show-CustomAppDialog ($($findNames.Count) total)"

    foreach ($m in $findNames) {
        $ctrlName = $m.Groups[1].Value
        Assert ($dialogXaml -match "x:Name=""$ctrlName""") "FindName('$ctrlName') has matching x:Name in XAML"
    }
}

# -----------------------------------------------------------------------
# 3. Search-WingetApps parser -- extract function and test with canned data
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Search-WingetApps parser (canned winget output) ---'

$searchFuncDef = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Search-WingetApps'
}, $true)

Assert ($null -ne $searchFuncDef) 'Search-WingetApps AST node found'

if ($null -ne $searchFuncDef) {
    # Define the real function in this scope
    . ([scriptblock]::Create($searchFuncDef.Extent.Text))

    # Mock winget to return canned table output without hitting the network
    function winget {
        @(
            'Name                         Id                              Version   Match        Source',
            '--------------------------------------------------------------------------------------------',
            'Git                          Git.Git                         2.43.0               winget',
            'GitHub Desktop               GitHub.GitHubDesktop            3.3.8                winget',
            'GitExtensions                GitExtensionsTeam.GitExtensions 4.2.1                winget'
        )
    }

    $results = Search-WingetApps -Query 'git'

    Assert ($results.Count -eq 3)                              'Parser finds all 3 data rows'
    Assert ($results[0].Id -eq 'Git.Git')                      'First result ID correct'
    Assert ($results[1].Id -eq 'GitHub.GitHubDesktop')         'Second result ID correct'
    Assert ($results[2].Id -eq 'GitExtensionsTeam.GitExtensions') 'Third result ID correct'
    Assert ($results[0].Name -match 'Git')                     'First result Name populated'
    Assert ($results[0].Version -eq '2.43.0')                  'First result Version populated'

    # Empty results: winget returns "No package found"
    function winget {
        @('No package found matching input criteria.')
    }
    $empty = Search-WingetApps -Query 'zzznomatch'
    Assert ($empty.Count -eq 0) 'Returns empty array when no header row found'

    # Error handling: winget throws
    function winget {
        throw 'winget not available'
    }
    $errResult = Search-WingetApps -Query 'anything'
    Assert ($errResult.Count -eq 0) 'Returns empty array on winget exception'
}

# -----------------------------------------------------------------------
# 4. Save-UserManifest -- round-trip file I/O in temp directory
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Save-UserManifest file I/O ---'

$saveFuncDef = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Save-UserManifest'
}, $true)

Assert ($null -ne $saveFuncDef) 'Save-UserManifest AST node found'

if ($null -ne $saveFuncDef) {
    . ([scriptblock]::Create($saveFuncDef.Extent.Text))

    # Redirect APPDATA to a temp folder so we do not touch real user data
    $oldAppData = $env:APPDATA
    $tempRoot   = Join-Path $env:TEMP "LoadoutTest-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    $env:APPDATA = $tempRoot

    try {
        $expectedPath = Join-Path $tempRoot 'Loadout\user-manifest.json'

        # Test 1: create from scratch
        $app1 = [PSCustomObject]@{
            id          = 'custom-test-alpha'
            displayName = 'Test Alpha'
            wingetId    = 'Test.Alpha'
        }
        Save-UserManifest -NewApp $app1
        Assert (Test-Path $expectedPath) 'user-manifest.json created by Save-UserManifest'

        $loaded = Get-Content $expectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert ($loaded.apps.Count -eq 1)                    'Saved manifest has 1 app'
        Assert ($loaded.apps[0].id -eq 'custom-test-alpha')  'Saved app ID correct'
        Assert ($loaded.apps[0].displayName -eq 'Test Alpha') 'Saved app displayName correct'
        Assert ($loaded.apps[0].wingetId -eq 'Test.Alpha')    'Saved app wingetId correct'

        # Test 2: add a second app without overwriting the first
        $app2 = [PSCustomObject]@{
            id          = 'custom-test-beta'
            displayName = 'Test Beta'
            wingetId    = 'Test.Beta'
        }
        Save-UserManifest -NewApp $app2
        $loaded2 = Get-Content $expectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert ($loaded2.apps.Count -eq 2)                   'Second Save adds to existing (2 apps total)'
        $ids = @($loaded2.apps | ForEach-Object { $_.id })
        Assert ($ids -contains 'custom-test-alpha')           'Original app preserved after second save'
        Assert ($ids -contains 'custom-test-beta')            'New app present after second save'

        # Test 3: overwrite by ID -- saving same ID replaces the entry
        $app1Updated = [PSCustomObject]@{
            id          = 'custom-test-alpha'
            displayName = 'Test Alpha Updated'
            wingetId    = 'Test.AlphaV2'
        }
        Save-UserManifest -NewApp $app1Updated
        $loaded3 = Get-Content $expectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert ($loaded3.apps.Count -eq 2)                      'Count unchanged after ID-replace save'
        $updated = $loaded3.apps | Where-Object { $_.id -eq 'custom-test-alpha' } | Select-Object -First 1
        Assert ($updated.displayName -eq 'Test Alpha Updated')  'Replaced app has updated displayName'
        Assert ($updated.wingetId -eq 'Test.AlphaV2')           'Replaced app has updated wingetId'

    } finally {
        $env:APPDATA = $oldAppData
        if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
    }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ''
Write-Host "Results: $pass passed, $fail failed."
if ($fail -gt 0) { exit 1 }
Write-Host 'All assertions passed.'
