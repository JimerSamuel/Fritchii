# Fritchii - pruebas A/B para Intel Arc
# Uso: powershell -ExecutionPolicy Bypass -File arc_test.ps1 -Exe "C:\ruta\lichii.exe"
# Cada prueba abre el emulador con una variable distinta. Entra al juego, quedate
# ~90 segundos en el MISMO lugar, cierra el emulador y el script pasa a la siguiente.
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string[]]$Only
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Exe)) { throw "No existe: $Exe" }

$log = Join-Path $env:APPDATA "eden\log\eden_log.txt"
$out = Join-Path $PSScriptRoot ("results_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force (Join-Path $out "shaders") | Out-Null

# Nombre -> variables de entorno. GPU_PROFILE va en todas para medir donde se va el tiempo.
$tests = [ordered]@{
    "A_base"        = @{ EDEN_NX2_GPU_PROFILE = "1" }
    "B_exp12_1"     = @{ EDEN_NX2_GPU_PROFILE = "1"; EDEN_NX2_EXP12 = "1" }
    "C_exp12_2"     = @{ EDEN_NX2_GPU_PROFILE = "1"; EDEN_NX2_EXP12 = "2" }
    "D_frame_trace" = @{ EDEN_NX2_GPU_PROFILE = "1"; EDEN_DKB_FRAME_TRACE = "1"; EDEN_NX2_SHADER_DUMP = "__OUT__\shaders" }
}

foreach ($name in $tests.Keys) {
    if ($Only -and ($Only -notcontains $name)) { continue }
    Write-Host ""
    Write-Host "=== Prueba $name ===" -ForegroundColor Cyan
    Write-Host "Entra al juego, quedate ~90 s en el mismo sitio y cierra el emulador."
    $vars = $tests[$name]
    $psi = New-Object System.Diagnostics.ProcessStartInfo $Exe
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = Split-Path $Exe
    foreach ($k in $vars.Keys) { $psi.EnvironmentVariables[$k] = $vars[$k].Replace("__OUT__", $out) }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    Start-Sleep -Seconds 2
    if (Test-Path $log) {
        Copy-Item $log (Join-Path $out "$name.txt")
        $frames = Select-String -Path $log -Pattern "last 600 presents: frame (\d+) us" |
            ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
        if ($frames) {
            $avg = ($frames | Measure-Object -Average).Average
            Write-Host ("  Media: {0:N1} ms por frame = {1:N1} FPS" -f ($avg / 1000), (1e6 / $avg)) -ForegroundColor Green
        } else {
            Write-Host "  Sin datos de frames (juega mas de ~30 s)." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Listo. Logs guardados en: $out" -ForegroundColor Cyan
