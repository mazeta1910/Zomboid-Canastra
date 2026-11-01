# Liga a pasta do mod deste repositorio a %USERPROFILE%\Zomboid\mods\Canastra (junction),
# para que o jogo carregue o codigo direto daqui. Use -Remove para desfazer.
param([switch]$Remove)

$source = Join-Path $PSScriptRoot "Contents\mods\Canastra"
$modsDir = Join-Path $env:USERPROFILE "Zomboid\mods"
$target = Join-Path $modsDir "Canastra"

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -ne "Junction") {
        Write-Error "$target ja existe e nao e um link. Remova ou renomeie manualmente."
        exit 1
    }
    $item.Delete()
    Write-Host "Link removido: $target"
}

if ($Remove) { exit 0 }

New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Mod instalado: $target -> $source"
