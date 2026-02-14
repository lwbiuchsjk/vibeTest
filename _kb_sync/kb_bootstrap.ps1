param(
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
$bindingPath = Join-Path $scriptDir 'kb.binding.json'
$localPath = Join-Path $scriptDir 'kb.local.json'
$cacheMdPath = Join-Path $scriptDir 'KB_CONTEXT.md'
$cacheJsonPath = Join-Path $scriptDir 'KB_CONTEXT.json'
$readTokenScript = Join-Path $scriptDir 'read_token.js'

function LogInfo([string]$msg) {
  if (-not $Quiet) { Write-Host "[kb-sync] $msg" }
}

function Resolve-RelPath([string]$baseDir, [string]$p) {
  if (-not $p) { return '' }
  if ([System.IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path $baseDir $p)
}

function Resolve-NodeExe {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $base = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  $cands = Get-ChildItem -Path $base -Directory -Filter 'OpenJS.NodeJS.LTS_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue } |
    ForEach-Object { Join-Path $_.FullName 'node.exe' } |
    Where-Object { Test-Path $_ }

  return $cands | Select-Object -First 1
}

function Resolve-LarkRoot {
  $hardcoded = 'D:\softwares\Nodejs\node_global\node_modules\@larksuiteoapi\lark-mcp'
  if (Test-Path $hardcoded) { return $hardcoded }

  $cmd = Get-Command npm -ErrorAction SilentlyContinue
  if ($cmd) {
    $npmRoot = (& npm root -g 2>$null | Select-Object -First 1)
    if ($npmRoot) {
      $candidate = Join-Path $npmRoot '@larksuiteoapi\lark-mcp'
      if (Test-Path $candidate) { return $candidate }
    }
  }

  $appDataCandidate = Join-Path $env:APPDATA 'npm\node_modules\@larksuiteoapi\lark-mcp'
  if (Test-Path $appDataCandidate) { return $appDataCandidate }

  return ''
}

function Normalize-DocLang([object]$v) {
  if ($null -eq $v) { return 0 }

  # API accepts lang as enum: 0/1/2 (see error: options [0,1,2]).
  # Accept ints directly, or common strings in local config.
  if ($v -is [int]) { return $v }
  $s = ([string]$v).Trim().ToLowerInvariant()
  if (-not $s) { return 0 }

  $asInt = 0
  if ([int]::TryParse($s, [ref]$asInt)) { return $asInt }

  switch ($s) {
    '0' { return 0 }
    '1' { return 1 }
    '2' { return 2 }
    'zh' { return 0 }
    'cn' { return 0 }
    'zh_cn' { return 0 }
    'zh-cn' { return 0 }
    'en' { return 1 }
    'ja' { return 2 }
    'jp' { return 2 }
    default { return 0 }
  }
}

if (-not (Test-Path $bindingPath)) {
  throw "Binding file not found: $bindingPath"
}

$binding = Get-Content -Raw $bindingPath | ConvertFrom-Json

$local = $null
if (Test-Path $localPath) {
  try {
    $local = Get-Content -Raw $localPath | ConvertFrom-Json
    LogInfo "Loaded local overrides: $localPath"
  } catch {
    throw "Failed to parse $localPath as JSON: $($_.Exception.Message)"
  }
}

$spaceId = $binding.spaceId
if ($local -and $local.spaceId) { $spaceId = $local.spaceId }
if (-not $spaceId) { throw 'spaceId is required (kb.binding.json or kb.local.json)' }

$appConfigRel = $binding.appConfigPath
if ($local -and $local.appConfigPath) { $appConfigRel = $local.appConfigPath }
if (-not $appConfigRel) { $appConfigRel = '../lark-mcp.config.json' }
$appConfigPath = Resolve-Path (Join-Path $scriptDir $appConfigRel)
$config = Get-Content -Raw $appConfigPath | ConvertFrom-Json

$appId = $config.appId
if (-not $appId) { throw "appId missing in $appConfigPath" }

$domain = $config.domain
if (-not $domain) { $domain = 'https://open.feishu.cn' }
$domain = $domain.TrimEnd('/')

$nodeExe = Resolve-NodeExe
if (-not $nodeExe) { throw 'node.exe not found. install Node.js LTS first.' }

$larkRoot = Resolve-LarkRoot
if (-not $larkRoot) { throw 'Cannot locate @larksuiteoapi/lark-mcp installation.' }

LogInfo "Using lark-mcp root: $larkRoot"

$tokenRaw = & $nodeExe $readTokenScript --larkRoot $larkRoot --appId $appId
$tokenInfo = $tokenRaw | ConvertFrom-Json
if (-not $tokenInfo.ok) {
  throw "Failed to read user token: $($tokenInfo.error)"
}

$userToken = $tokenInfo.userAccessToken
$headers = @{ Authorization = "Bearer $userToken" }

$spaceResp = Invoke-RestMethod -Method Get -Uri "$domain/open-apis/wiki/v2/spaces/$spaceId" -Headers $headers
if ($spaceResp.code -ne 0) { throw "space query failed: $($spaceResp.msg)" }

$allNodes = @()
$pageToken = ''
$hasMore = $true
while ($hasMore) {
  $url = "$domain/open-apis/wiki/v2/spaces/$spaceId/nodes?page_size=50"
  if ($pageToken) {
    $url += "&page_token=$([uri]::EscapeDataString($pageToken))"
  }

  $nodeResp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
  if ($nodeResp.code -ne 0) { throw "nodes query failed: $($nodeResp.msg)" }

  if ($nodeResp.data.items) { $allNodes += $nodeResp.data.items }
  $hasMore = [bool]$nodeResp.data.has_more
  $pageToken = [string]$nodeResp.data.page_token
}

$space = $spaceResp.data.space
$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

$md = @()
$md += '# Feishu KB Context'
$md += ''
$md += "- GeneratedAt: $generated"
$md += "- SpaceId: $($space.space_id)"
$md += "- SpaceName: $($space.name)"
$md += "- Visibility: $($space.visibility)"
$md += "- NodeCount: $($allNodes.Count)"
$md += "- Scopes: $([string]::Join(', ', $tokenInfo.scopes))"
$md += ''
$md += '## Nodes'
$md += ''

if ($allNodes.Count -eq 0) {
  $md += '- (no nodes visible)'
} else {
  foreach ($n in $allNodes) {
    $md += "- [$($n.obj_type)] $($n.title)"
    $md += "  - node_token: $($n.node_token)"
    $md += "  - obj_token: $($n.obj_token)"
  }
}

$mdText = ($md -join "`r`n") + "`r`n"
Set-Content -Path $cacheMdPath -Value $mdText -Encoding UTF8

$jsonOut = [ordered]@{
  generatedAt = $generated
  space = $space
  nodes = $allNodes
  scopes = $tokenInfo.scopes
}
$jsonOut | ConvertTo-Json -Depth 8 | Set-Content -Path $cacheJsonPath -Encoding UTF8

LogInfo "KB synced: $($space.name) / nodes=$($allNodes.Count)"

# Optional: cache docx raw_content locally so agents can read without hitting network each time.
$cacheEnabled = $false
$cacheDir = Join-Path $scriptDir 'cache'
$bundlePath = Join-Path $scriptDir 'KB_CACHE.md'
$indexPath = Join-Path $scriptDir 'cache_index.json'
$cacheLang = 0
$cacheTtlHours = 24
$includeNodeTokens = @()

if ($local) {
  if ($null -ne $local.cache.enabled) { $cacheEnabled = [bool]$local.cache.enabled }
  if ($local.cache.dir) { $cacheDir = Resolve-RelPath $scriptDir ([string]$local.cache.dir) }
  if ($local.cache.bundlePath) { $bundlePath = Resolve-RelPath $scriptDir ([string]$local.cache.bundlePath) }
  if ($local.cache.indexPath) { $indexPath = Resolve-RelPath $scriptDir ([string]$local.cache.indexPath) }
  if ($null -ne $local.cache.lang) { $cacheLang = Normalize-DocLang $local.cache.lang }
  if ($local.cache.ttlHours) { $cacheTtlHours = [int]$local.cache.ttlHours }
  if ($local.includeNodeTokens) { $includeNodeTokens = @($local.includeNodeTokens) }
}

if ($cacheEnabled) {
  LogInfo "Caching enabled. dir=$cacheDir ttlHours=$cacheTtlHours"
  New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

  $selected = $allNodes | Where-Object { $_.obj_type -eq 'docx' }
  if ($includeNodeTokens.Count -gt 0) {
    $tokenSet = @{}
    foreach ($t in $includeNodeTokens) { if ($t) { $tokenSet[[string]$t] = $true } }
    $selected = $selected | Where-Object { $tokenSet.ContainsKey([string]$_.node_token) }
  }

  $cacheIndex = @()
  foreach ($n in $selected) {
    $docId = [string]$n.obj_token
    if (-not $docId) { continue }

    $cacheFile = Join-Path $cacheDir ("docx_{0}.txt" -f $docId)
    $needFetch = $true
    if (Test-Path $cacheFile) {
      if ($cacheTtlHours -le 0) {
        $needFetch = $false
      } else {
        $age = (New-TimeSpan -Start (Get-Item $cacheFile).LastWriteTime -End (Get-Date)).TotalHours
        if ($age -lt $cacheTtlHours) { $needFetch = $false }
      }
    }

    if ($needFetch) {
      LogInfo "Fetching docx raw_content: $($n.title) ($docId)"
      $docUrl = "$domain/open-apis/docx/v1/documents/$docId/raw_content?lang=$cacheLang"
      $docResp = Invoke-RestMethod -Method Get -Uri $docUrl -Headers $headers
      if ($docResp.code -ne 0) { throw "docx raw_content failed ($docId): $($docResp.msg)" }
      $content = [string]$docResp.data.content
      Set-Content -Path $cacheFile -Value $content -Encoding UTF8
    } else {
      LogInfo "Cache hit: $($n.title) ($docId)"
    }

    $fi = Get-Item $cacheFile
    $cacheIndex += [ordered]@{
      node_token = [string]$n.node_token
      obj_type = [string]$n.obj_type
      obj_token = $docId
      title = [string]$n.title
      cache_file = [string]$cacheFile
      cached_at = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
      bytes = [int]$fi.Length
    }
  }

  $cacheIndex | ConvertTo-Json -Depth 6 | Set-Content -Path $indexPath -Encoding UTF8

  $bundle = @()
  $bundle += '# Feishu KB Cache'
  $bundle += ''
  $bundle += "- GeneratedAt: $generated"
  $bundle += "- SpaceId: $($space.space_id)"
  $bundle += "- SpaceName: $($space.name)"
  $bundle += "- DocsCached: $($cacheIndex.Count)"
  $bundle += ''

  foreach ($e in $cacheIndex) {
    $bundle += "## [docx] $($e.title)"
    $bundle += ''
    $bundle += "- node_token: $($e.node_token)"
    $bundle += "- obj_token: $($e.obj_token)"
    $bundle += "- cached_at: $($e.cached_at)"
    $bundle += ''
    $bundle += '```text'
    $bundle += (Get-Content -Raw $e.cache_file)
    $bundle += '```'
    $bundle += ''
  }

  Set-Content -Path $bundlePath -Value (($bundle -join "`r`n") + "`r`n") -Encoding UTF8
  LogInfo "KB cache bundle written: $bundlePath"
}
