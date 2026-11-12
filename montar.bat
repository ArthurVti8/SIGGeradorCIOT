@echo off
rem Monta o pacote do Gerador de CIOT na subpasta GeradorCIOT (duplo clique para rodar).
rem Leva cerca de 1 minuto e meio na primeira vez (baixa as DLLs da ANTT e o instalador do .NET).
title Montar pacote do Gerador de CIOT
echo Montando o pacote do Gerador de CIOT. Aguarde...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0montar.ps1" %*
if errorlevel 1 (
  echo.
  echo *** ERRO: o pacote NAO foi montado. Veja a mensagem acima. ***
) else (
  echo.
  echo Pacote montado com sucesso na pasta GeradorCIOT.
)
echo.
pause
