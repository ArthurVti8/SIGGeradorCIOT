# Monta as pastas do GeradorCIOTPonte para instalar em C:\VTi\GeradorCIOT\
#   <Destino>\Homologacao\  -> DLL oficial de homologação da ANTT
#   <Destino>\Producao\     -> DLL oficial de produção da ANTT
# Cada pasta: GeradorCIOTPonte.exe + .config + GeradorCIOTShared.dll (ANTT) + dependências (NuGet).
# Nada é executado contra a ANTT aqui: só download e compilação.
#
# Uso: duplo clique no montar.bat (mostra o andamento e espera um Enter no fim), ou
#      powershell -ExecutionPolicy Bypass -File montar.ps1 [-Destino <pasta>]

# Sem -Destino, monta na subpasta GeradorCIOT\ (é ela que vai para a pasta VTI do cliente;
# o .gitignore ignora os binários)
param([string]$Destino = (Join-Path $PSScriptRoot 'GeradorCIOT'))

$ErrorActionPreference = 'Stop'
# No PowerShell 5.1 a barra de progresso deixa downloads grandes muito lentos
# (o instalador do .NET tem 121 MB)
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$trabalho = Join-Path $env:TEMP ('GeradorCIOTPonte_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$trabalho\pkg", "$trabalho\lib", "$trabalho\antt" | Out-Null

# A pasta de trabalho é apagada no fim, mesmo se der erro
try {

# 1. Dependências do System.Text.Json 5.0 para .NET Framework (NuGet)
Write-Output '1/6 Baixando as dependências do NuGet...'
$pacotes = @(
  @('System.Text.Json', '5.0.0', 'net461'),
  @('Microsoft.Bcl.AsyncInterfaces', '5.0.0', 'net461'),
  @('System.Buffers', '4.5.1', 'net461'),
  @('System.Memory', '4.5.4', 'net461'),
  @('System.Numerics.Vectors', '4.5.0', 'net46'),
  @('System.Runtime.CompilerServices.Unsafe', '5.0.0', 'net45'),
  @('System.Text.Encodings.Web', '5.0.0', 'net461'),
  @('System.Threading.Tasks.Extensions', '4.5.4', 'net461'),
  @('System.ValueTuple', '4.5.0', 'net461')
)
foreach ($p in $pacotes) {
  $id, $ver, $tfm = $p
  $nupkg = "$trabalho\pkg\$id.$ver.nupkg"
  Invoke-WebRequest "https://www.nuget.org/api/v2/package/$id/$ver" -OutFile $nupkg -UseBasicParsing
  $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
  try {
    $ent = $zip.Entries | Where-Object { $_.FullName -eq "lib/$tfm/$id.dll" } | Select-Object -First 1
    if (-not $ent) { throw "lib/$tfm/$id.dll não encontrado em $id $ver" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($ent, "$trabalho\lib\$id.dll", $true)
  } finally { $zip.Dispose() }
}

# 2. DLLs oficiais da ANTT (página "Documentos Técnicos" do CIOT para Todos)
Write-Output '2/6 Baixando as DLLs oficiais da ANTT...'
$antt = @{
  'Homologacao' = 'https://appservices-hml.antt.gov.br/pefServices/Downloads/GeradorCIOT_DLL.zip'
  'Producao'    = 'https://appservices.antt.gov.br/pefServices/Downloads/GeradorCIOT_DLL.zip'
}
foreach ($amb in $antt.Keys) {
  $z = "$trabalho\antt\$amb.zip"
  Invoke-WebRequest $antt[$amb] -OutFile $z -UseBasicParsing
  Expand-Archive $z -DestinationPath "$trabalho\antt\$amb" -Force
}

# 3. Conferência do ambiente de cada DLL (mesma regra da trava do uPefANTT)
Write-Output '3/6 Conferindo o ambiente de cada DLL...'
function ContemUTF16([string]$arquivo, [string]$texto) {
  $b = [BitConverter]::ToString([IO.File]::ReadAllBytes($arquivo))
  return $b.Contains([BitConverter]::ToString([Text.Encoding]::Unicode.GetBytes($texto)))
}
$urlHml = 'https://appservices-hml.antt.gov.br/pefServices'
$marcaPrd = '/api-ciot-prd/'
$dllHml = (Get-ChildItem "$trabalho\antt\Homologacao" -Recurse -Filter GeradorCIOTShared.dll | Select-Object -First 1).FullName
$dllPrd = (Get-ChildItem "$trabalho\antt\Producao" -Recurse -Filter GeradorCIOTShared.dll | Select-Object -First 1).FullName
if (-not ((ContemUTF16 $dllHml $urlHml) -and -not (ContemUTF16 $dllHml $marcaPrd))) { throw 'A DLL baixada de homologação não aponta para a homologação.' }
if (-not ((ContemUTF16 $dllPrd $marcaPrd) -and -not (ContemUTF16 $dllPrd $urlHml))) { throw 'A DLL baixada de produção não tem a marca de produção esperada (a ANTT pode ter mudado o endereço; revisar a trava do uPefANTT).' }

# 4. Compila a ponte (csc do .NET Framework do Windows)
Write-Output '4/6 Compilando a ponte...'
$csc ='C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
$exe = "$trabalho\GeradorCIOTPonte.exe"
& $csc /nologo /target:exe /platform:anycpu /optimize+ /out:$exe /reference:$dllHml `
  /reference:C:\Windows\Microsoft.NET\Framework\v4.0.30319\netstandard.dll (Join-Path $PSScriptRoot 'Program.cs')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o GeradorCIOTPonte.exe' }

# 5. Monta as pastas
Write-Output "5/6 Montando as pastas em $Destino ..."
foreach ($amb in @('Homologacao', 'Producao')) {
  $pasta = Join-Path $Destino $amb
  New-Item -ItemType Directory -Force $pasta | Out-Null
  Copy-Item $exe, (Join-Path $PSScriptRoot 'GeradorCIOTPonte.exe.config') $pasta -Force
  Copy-Item "$trabalho\lib\*.dll" $pasta -Force
  $dll = if ($amb -eq 'Homologacao') { $dllHml } else { $dllPrd }
  Copy-Item $dll $pasta -Force
  Write-Output "Montado: $pasta"
}

# 6. Instalador offline do .NET Framework 4.8 (para máquinas sem o 4.7.2+),
#    na raiz do pacote. Confere a assinatura da Microsoft antes de copiar.
#    Se já estiver na pasta com a assinatura válida, não baixa de novo.
$instalador = Join-Path $Destino 'Instalar .NET Framework 4.8.exe'
function InstaladorValido([string]$arquivo) {
  if (-not (Test-Path $arquivo)) { return $false }
  $a = Get-AuthenticodeSignature $arquivo
  return ($a.Status -eq 'Valid' -and $a.SignerCertificate.Subject -match 'O=Microsoft Corporation' -and
          (Get-Item $arquivo).VersionInfo.ProductVersion -like '4.8.*')
}
if (InstaladorValido $instalador) {
  Write-Output '6/6 Instalador do .NET Framework 4.8 já está na pasta (assinatura válida).'
} else {
  Write-Output '6/6 Baixando o instalador do .NET Framework 4.8 (121 MB)...'
  $net48 = "$trabalho\ndp48-x86-x64-allos-enu.exe"
  Invoke-WebRequest 'https://go.microsoft.com/fwlink/?linkid=2088631' -OutFile $net48 -UseBasicParsing
  if (-not (InstaladorValido $net48)) {
    throw 'O instalador do .NET baixado não tem assinatura válida da Microsoft.'
  }
  Copy-Item $net48 $instalador -Force
}
Write-Output "Instalador do .NET: $instalador"

} finally {
  Remove-Item $trabalho -Recurse -Force -ErrorAction SilentlyContinue
}
