# panel.ps1 - maly panel do codziennej petli moddowania
# Odpalanie: gui\panel.bat  (albo: powershell -ExecutionPolicy Bypass -File gui\panel.ps1)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$ROOT  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PATCH = "C:\Users\PC\Documents\goh-hf-patch"
$MOD   = "C:\Program Files (x86)\Steam\steamapps\workshop\content\400750\3359417100\resource"
$LOG   = "$env:USERPROFILE\Documents\My Games\gates of hell\log\game.log"
$EXE   = "C:\Program Files (x86)\Steam\steamapps\common\Call to Arms - Gates of Hell\binaries\x64\call_to_arms.exe"

$f = New-Object Windows.Forms.Form
$f.Text = "GoH - panel"
$f.Size = New-Object Drawing.Size(880, 620)
$f.StartPosition = "CenterScreen"
$f.BackColor = [Drawing.Color]::FromArgb(32,34,37)

$out = New-Object Windows.Forms.TextBox
$out.Multiline = $true; $out.ScrollBars = "Vertical"; $out.ReadOnly = $true
$out.Font = New-Object Drawing.Font("Consolas", 9)
$out.BackColor = [Drawing.Color]::FromArgb(24,26,28)
$out.ForeColor = [Drawing.Color]::Gainsboro
$out.Location = New-Object Drawing.Point(12, 92)
$out.Size = New-Object Drawing.Size(840, 440)
$out.Anchor = "Top,Left,Right,Bottom"
$f.Controls.Add($out)

$bar = New-Object Windows.Forms.Label
$bar.Location = New-Object Drawing.Point(12, 542)
$bar.Size = New-Object Drawing.Size(840, 22)
$bar.ForeColor = [Drawing.Color]::Gainsboro
$bar.Anchor = "Left,Right,Bottom"
$f.Controls.Add($bar)

function Say($t, $clear = $false) {
    if ($clear) { $out.Text = "" }
    $out.AppendText(($t -join "`r`n") + "`r`n")
    $out.SelectionStart = $out.TextLength; $out.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

function GameRunning { [bool](Get-Process call_to_arms -ErrorAction SilentlyContinue) }

function Status {
    $g = if (GameRunning) { "GRA CHODZI - zmiany nie wejda, mody montuja sie na starcie" }
         else { "gra zamknieta" }
    $n = if (Test-Path "$PATCH\resource") { (Get-ChildItem "$PATCH\resource" -Recurse -File).Count } else { "?" }
    $bar.Text = "  $g   |   patch: $n plikow   |   $(Get-Date -f 'HH:mm:ss')"
    $bar.ForeColor = if (GameRunning) { [Drawing.Color]::Gold } else { [Drawing.Color]::FromArgb(120,200,120) }
}

function Btn($text, $x, $y, $w, $act) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, 34)
    $b.FlatStyle = "Flat"
    $b.BackColor = [Drawing.Color]::FromArgb(54,57,63)
    $b.ForeColor = [Drawing.Color]::Gainsboro
    $b.Add_Click($act)
    $f.Controls.Add($b)
    $b
}

# --- rzad 1 ---
Btn "Sprawdz pliki" 12 12 130 {
    Say "=== preflight ===", $true
    Say (& perl "$ROOT\test\preflight.pl" 2>&1)
    Status
} | Out-Null

Btn "Delta" 150 12 90 {
    Say "=== nasze zmiany wzgledem zrodel ===", $true
    if (-not (Test-Path "$PATCH\upstream")) { Say "brak upstream/ - kliknij Snapshot"; return }
    $sum = 0
    Get-ChildItem "$PATCH\resource" -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring("$PATCH\resource".Length + 1)
        $u = "$PATCH\upstream\$rel"
        if (Test-Path $u) {
            $d = (Compare-Object (Get-Content $u) (Get-Content $_.FullName)).Count
            $sum += $d
            Say ("  {0,-54} {1,4} linii" -f $rel, $d)
        }
    }
    Say "", "  RAZEM: $sum linii"
} | Out-Null

Btn "Snapshot zrodel" 248 12 140 {
    Say "=== snapshot-upstream ===", $true
    Say (& perl "$ROOT\test\snapshot-upstream.pl" 2>&1)
} | Out-Null

Btn "Wdroz do moda" 396 12 130 {
    if (GameRunning) { Say "GRA CHODZI - zamknij najpierw.", $true; return }
    Say "=== kopiuje patch do moda ===", $true
    $n = 0
    Get-ChildItem "$PATCH\resource" -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring("$PATCH\resource".Length + 1)
        $dst = Join-Path $MOD $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item $_.FullName $dst -Force
        $n++
    }
    Say "  skopiowano $n plikow"
    Say "", (& perl "$ROOT\test\preflight.pl" 2>&1 | Select-Object -Last 4)
    Status
} | Out-Null

Btn "Co jest w modzie" 534 12 140 {
    Say "=== luzne pliki w modzie poza patchem ===", $true
    $mine = @{}
    Get-ChildItem "$PATCH\resource" -Recurse -File | ForEach-Object {
        $mine[$_.FullName.Substring("$PATCH\resource".Length + 1)] = $true }
    $extra = @()
    Get-ChildItem $MOD -Recurse -File | Where-Object { $_.Extension -ne ".pak" } | ForEach-Object {
        $rel = $_.FullName.Substring($MOD.Length + 1)
        if ($rel -match '^(interface\\splash|map\\testing_ground|message\.txt)') { return }
        if (-not $mine.ContainsKey($rel)) { $extra += $rel }
    }
    if ($extra) { Say "  $($extra.Count) plikow eksperymentalnych:"; $extra | ForEach-Object { Say "     $_" } }
    else { Say "  czysto - tylko patch" }
} | Out-Null

# --- rzad 2 ---
Btn "Log: podsumowanie" 12 52 150 {
    Say "=== game.log ===", $true
    if (-not (Test-Path $LOG)) { Say "  brak logu"; return }
    $i = Get-Item $LOG
    Say ("  z {0}, {1:N0} B" -f $i.LastWriteTime, $i.Length), ""
    $t = Get-Content $LOG
    $ex = ($t | Select-String "\*\*\*\*\* Exception").Count
    Say ("  crashe             : {0}" -f $ex)
    Say ("  can't spawn        : {0}" -f ($t | Select-String "can't spawn entity").Count)
    Say ("  no breed found     : {0}   (szum, nie nasza wina)" -f ($t | Select-String "no breed found").Count)
    Say ("  not registerd      : {0}   (szum)" -f ($t | Select-String "not registerd in unit").Count)
    if ($ex) {
        Say "", "  --- CRASH ---"
        $n = ($t | Select-String "\*\*\*\*\* Exception" | Select-Object -First 1).LineNumber
        Say ($t[($n-1)..([Math]::Min($n+16, $t.Count-1))] | ForEach-Object { "  $_" })
    }
} | Out-Null

Btn "Log: nasze encje" 170 52 150 {
    Say "=== slady naszych encji w logu ===", $true
    if (-not (Test-Path $LOG)) { Say "  brak logu"; return }
    $h = Get-Content $LOG | Select-String "Remap actor_id|can't spawn entity|paradrop|para_drop|c47_d"
    if ($h) { $h | Select-Object -Last 30 | ForEach-Object { Say "  $($_.Line.Trim())" } }
    else { Say "  nic - sukcesy nie loguja sie, szukaj potwierdzenia na ekranie" }
} | Out-Null

Btn "Zachowaj log" 328 52 120 {
    if (-not (Test-Path $LOG)) { Say "  brak logu", $true; return }
    $d = "$ROOT\data\logi"; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $n = "$d\game_$(Get-Date -f 'MMdd_HHmm').log"
    Copy-Item $LOG $n
    Say "zapisane: $n", $true
    Say "", "(log kasuje sie przy kazdym starcie gry - rob to przed ponownym odpaleniem)"
} | Out-Null

Btn "Binarka: info" 456 52 120 {
    Say "=== goh.pl info ===", $true
    Say (& perl "$ROOT\pe\goh.pl" $EXE info 2>&1)
} | Out-Null

Btn "Odswiez" 584 52 90 { Status; Say "odswiezone $(Get-Date -f 'HH:mm:ss')", $true } | Out-Null

Status
Say @(
  "Panel do codziennej petli: sprawdz -> wdroz -> zagraj -> log.",
  "",
  "Kolejnosc, ktora sie sprawdza:",
  "  1. Sprawdz pliki    - musi dac 'mozesz testowac', inaczej crash w grze",
  "  2. Wdroz do moda    - tylko przy zamknietej grze, mody montuja sie na starcie",
  "  3. zagraj jedna bitwe, jedna zmiana naraz",
  "  4. Zachowaj log     - PRZED ponownym odpaleniem, log sie kasuje",
  "  5. Log: podsumowanie",
  ""
) $true

[void]$f.ShowDialog()
