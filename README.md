# SIGGeradorCIOT

Ponte entre o SIG (tela CIOT do Núcleo, componente `TPefANTT`) e a **biblioteca oficial da ANTT** que gera o número do CIOT (`GeradorCIOTShared.dll`).

## Por que existe

O manual da ANTT (DCS PEF v1.2) manda gerar o código da operação "utilizando a DLL/Executável disponibilizada". A DLL oficial faz a autenticação (token) e chama o serviço de geração. Em produção, esse serviço fica no API Gateway da ANTT na AWS (`.../api-ciot-prd/GeradorCIOT`), e não em `appservices.antt.gov.br`. Por isso, chamar o `/gerar` direto dava HTTP 500 em produção.

A DLL é .NET Standard 2.0 e não dá para chamar direto do Delphi. A ponte é um executável .NET Framework 4.7.2+ que só faz isto:

```
GeradorCIOTPonte.exe <cpfCnpj>
```

Ela imprime `CIOT=<12 dígitos>` em caso de sucesso, ou `ERRO=<mensagem>` em caso de falha. O código de saída é 0 para sucesso, 1 para falha e 2 para uso incorreto.

**TLS:** a ponte liga o TLS 1.2 no início (`ServicePointManager.SecurityProtocol`). Compilada pelo `csc` sem atributo de versão, o .NET usaria só SSL3/TLS 1.0. A homologação da ANTT aceita TLS 1.0, mas o gerador de produção (AWS) recusa com *"Não foi possível criar um canal seguro para SSL/TLS"*. Isso foi visto no primeiro cliente, em 12/11/2026.

## Arquivos

| Arquivo | O que é |
|---|---|
| `Program.cs` | fonte da ponte |
| `GeradorCIOTPonte.exe.config` | runtime 4.7.2 e redirecionamentos das dependências do System.Text.Json 5 |
| `montar.ps1` | gera os pacotes `Homologacao\` e `Producao\` e baixa o instalador do .NET |
| `LEIA-ME.txt` | instruções para instalar no cliente (vai junto com a pasta) |

Os binários (`Homologacao\`, `Producao\`, `*.exe`, `*.dll`) não ficam no Git: o `montar.ps1` gera tudo de novo. O instalador do .NET (121 MB) também não caberia, porque o GitHub recusa arquivos acima de 100 MB.

## Instalação no cliente

Uma pasta por ambiente, ao lado do `nucleo.exe`. **No cliente, o nome tem que ser `GeradorCIOT`**, sem o "SIG" deste repositório:

```
C:\VTi\GeradorCIOT\Homologacao\   (DLL de homologação da ANTT)
C:\VTi\GeradorCIOT\Producao\      (DLL de produção da ANTT)
```

A tela CIOT usa a pasta do ambiente configurado (`AMBIENTE_WS`).
- **Produção sem a pasta:** ao Enviar, avisa *"Pasta necessária para gerar o CIOT não encontrada"* e oferece digitar um código de CIOT.
- **Homologação sem a pasta:** pede o número direto ao `/gerar`, que lá funciona.

**Trava:** antes de rodar a ponte, o `TPefANTT` lê a `GeradorCIOTShared.dll` da pasta e confere se ela é do ambiente configurado. A de homologação tem o endereço `appservices-hml`; a de produção tem a marca `/api-ciot-prd/`. Se não for do ambiente certo, ele recusa sem enviar nada.

Requisito: .NET Framework 4.7.2 ou mais novo (Windows 10 e 11 já têm).

**Sem o .NET:** o `TPefANTT` confere o registro do Windows antes de rodar a ponte (`DotNetGeradorInstalado`). Se faltar o .NET, a tela CIOT avisa e pergunta se o usuário quer digitar um código de CIOT. O Núcleo não instala o .NET sozinho. As saídas são:
- instalar o .NET pelo `Instalar .NET Framework 4.8.exe`, que fica na raiz do pacote;
- digitar um código de CIOT de 12 dígitos gerado pelo Gerador de CIOT da ANTT, o programa com tela, que é autocontido e não precisa do .NET. Esse código vai em `CIOTInformado`.

## Como montar os pacotes

```
powershell -ExecutionPolicy Bypass -File montar.ps1 [-Destino "C:\algum\lugar"]
```

Sem `-Destino`, monta na própria pasta do repositório. O script:
1. baixa as dependências do NuGet;
2. baixa as duas DLLs da ANTT;
3. confere o ambiente de cada uma;
4. compila a ponte com o `csc.exe` do Windows;
5. monta `Homologacao\` e `Producao\`;
6. baixa o instalador offline do .NET Framework 4.8 e confere a assinatura da Microsoft.

Ele não chama nenhum serviço da ANTT.

Quando a ANTT publicar uma DLL nova, basta rodar o script de novo. Se o endereço de produção mudar, o script avisa: nesse caso, revisar a constante `MARCA_GERADOR_PRODUCAO` no `uPefANTT.pas`.

## Do lado do Delphi

- `Nucleo2\UnitCIOT.pas` (repositório VTiProjetos_RIO): tela CIOT, localiza a pasta, avisos de falta do .NET e da pasta.
- `C:\Componentes\PefANTT\uPefANTT.pas` (fora do Git): componente `TPefANTT`, que roda a ponte (`GeradorCIOTExe`), faz a trava de ambiente e a verificação do .NET e aceita o `CIOTInformado`.
