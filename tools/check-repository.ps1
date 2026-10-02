# Read-only checks of the Git-tracked draft. No hardware access.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tracked = @(& git -C $repoRoot ls-files)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) { throw 'Run after git add in this repository.' }
$issues = @()
foreach ($relative in $tracked) {
    $path = Join-Path $repoRoot $relative
    if ($relative -match '(^|/)(Build|Debug|Release|Backup|\.metadata)/|\.(elf|bin|hex|o|map|launch|zip)$') {
        $issues += "Unwanted generated/private artifact: $relative"
    }
    if ((Get-Item -LiteralPath $path).Length -gt 50MB) { $issues += "Large file: $relative" }
    if ($relative -match '\.(png|jpg|jpeg)$') { continue }
    $content = Get-Content -LiteralPath $path -Raw
    if ($content -match '[A-Za-z]:[/\\]Users[/\\]|(?<!\d)\d{24}(?!\d)|gh[pousr]_[A-Za-z0-9]{20,}|github[_]pat[_]|BEGIN (RSA |OPENSSH )?PRIVATE KEY') {
        $issues += "Private identifier/credential pattern: $relative"
    }
    if ($relative.EndsWith('.json')) { $null = $content | ConvertFrom-Json }
    if ($relative.EndsWith('.jsonl')) {
        foreach ($row in (Get-Content -LiteralPath $path)) { if ($row.Trim()) { $null = $row | ConvertFrom-Json } }
    }
    if ($relative.EndsWith('.md')) {
        foreach ($match in [regex]::Matches($content,'!?\[[^\]]*\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value
            if ($target -match '^(https?://|mailto:|#)') { continue }
            $target = ($target -split '#',2)[0]
            if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $path) $target))) {
                $issues += "Broken relative link in ${relative}: $target"
            }
        }
    }
}
if ($issues.Count) { $issues | ForEach-Object { Write-Host $_ }; throw 'Repository checks failed.' }
Write-Host "PASS: $($tracked.Count) tracked files; relative Markdown links, JSON/JSONL, artifact exclusions and selected privacy patterns checked."
Write-Host 'This is not an exhaustive secret scan or hardware test.'
