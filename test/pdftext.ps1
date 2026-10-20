# Wyciaga tekst z PDF: inflatuje strumienie FlateDecode i zbiera literaly ( ) oraz <hex>.
# Zachowuje czesciowy wynik, gdy inflate przerwie sie w polowie.
param([Parameter(Mandatory=$true)][string]$Path)

$bytes = [System.IO.File]::ReadAllBytes($Path)
$enc = [System.Text.Encoding]::GetEncoding(28591)   # latin1: bajty 1:1
$text = $enc.GetString($bytes)

function Inflate-Partial([byte[]]$data) {
    $ms = New-Object System.IO.MemoryStream(,$data)
    $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $outMs = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    try {
        while ($true) {
            $n = $ds.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $outMs.Write($buf, 0, $n)
        }
    } catch { }
    finally { try { $ds.Dispose() } catch {} }
    return $outMs.ToArray()
}

$out = New-Object System.Text.StringBuilder
$pos = 0
$n_ok = 0; $n_fail = 0
while ($true) {
    $s = $text.IndexOf("stream", $pos)
    if ($s -lt 0) { break }
    $p = $s + 6
    if ($p -lt $text.Length -and $text[$p] -eq "`r") { $p++ }
    if ($p -lt $text.Length -and $text[$p] -eq "`n") { $p++ }
    $e = $text.IndexOf("endstream", $p)
    if ($e -lt 0) { break }
    $len = $e - $p
    $pos = $e + 9
    if ($len -le 2) { continue }

    $chunk = New-Object byte[] ($len - 2)
    [Array]::Copy($bytes, $p + 2, $chunk, 0, $len - 2)   # pomin 2-bajtowy naglowek zlib
    $raw = Inflate-Partial $chunk
    if ($raw.Length -eq 0) { $n_fail++; continue }
    $page = $enc.GetString($raw)
    if ($page -notmatch 'TJ|Tj') { continue }
    $n_ok++

    # literaly ( ... ) oraz <hex>
    foreach ($m in [regex]::Matches($page, '\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f\s]+>')) {
        $v = $m.Value
        if ($v.StartsWith('<')) {
            $h = ($v.Trim('<', '>') -replace '\s', '')
            if ($h.Length % 4 -eq 0) {
                for ($i = 0; $i -lt $h.Length; $i += 4) {
                    $c = [Convert]::ToInt32($h.Substring($i, 4), 16)
                    if ($c -ge 32 -and $c -lt 65536) { [void]$out.Append([char]$c) }
                }
            }
            continue
        }
        $v = $v.Substring(1, $v.Length - 2)
        $v = $v -replace '\\\(', '(' -replace '\\\)', ')' -replace '\\\\', '\'
        [void]$out.Append($v)
    }
    [void]$out.Append("`n--- [strumien $n_ok] ---`n")
}
Write-Host "strumienie z tekstem: $n_ok, nieudane inflate: $n_fail" -ForegroundColor Cyan
$out.ToString()
