$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = 'H:\www\window_guard'
$localAlerts = 'C:\Users\ben\Documents\Codex\2026-10-13\hey\outputs\window-guard\data\alerts'
$eventDir = Join-Path $repo 'events'
$lockPath = Join-Path $repo '.publisher.lock'

if (Test-Path -LiteralPath $lockPath) {
    $age = (Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime
    if ($age.TotalMinutes -lt 10) { exit 0 }
}
Set-Content -LiteralPath $lockPath -Value $PID -Encoding ascii

try {
    New-Item -ItemType Directory -Path $eventDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'latest.jpg') -Destination (Join-Path $repo 'latest.jpg') -Force
    Copy-Item -LiteralPath (Join-Path $source 'status.json') -Destination (Join-Path $repo 'status.json') -Force

    $items = @()
    $galleryPath = Join-Path $source 'gallery.json'
    if (Test-Path -LiteralPath $galleryPath) {
        $gallery = @(Get-Content -Raw -LiteralPath $galleryPath | ConvertFrom-Json)
        foreach ($entry in $gallery | Select-Object -First 20) {
            $name = Split-Path -Leaf ([string]$entry.image_url)
            $imageSource = Join-Path (Join-Path $source 'alerts') $name
            if (Test-Path -LiteralPath $imageSource) {
                Copy-Item -LiteralPath $imageSource -Destination (Join-Path $eventDir $name) -Force
                $items += [ordered]@{created_at=$entry.created_at;title=$entry.title;image="events/$name"}
            }
        }
    }

    if ($items.Count -eq 0 -and (Test-Path -LiteralPath $localAlerts)) {
        foreach ($file in Get-ChildItem -LiteralPath $localAlerts -File -Filter '*.jpg' | Sort-Object LastWriteTime -Descending | Select-Object -First 20) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $eventDir $file.Name) -Force
            $items += [ordered]@{created_at=$file.LastWriteTime.ToUniversalTime().ToString('o');title='Detected visual change';image="events/$($file.Name)"}
        }
    }

    ConvertTo-Json -InputObject @($items) -Depth 4 | Set-Content -LiteralPath (Join-Path $repo 'events.json') -Encoding utf8
    if ($items.Count -eq 0) { Set-Content -LiteralPath (Join-Path $repo 'events.json') -Value '[]' -Encoding utf8 }

    git -C $repo add --all
    git -C $repo diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $repo commit -m ("Update Window Guard " + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
        git -C $repo push origin main
        if ($LASTEXITCODE -ne 0) { throw "Git push failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
