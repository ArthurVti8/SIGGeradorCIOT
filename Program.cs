using System;
using System.Net;
using System.Text;

namespace VTi.CIOT
{
    // Ponte entre o SIG (Delphi) e a biblioteca oficial da ANTT de geração do
    // código do CIOT (GeradorCIOTShared.dll, baixada do site da ANTT).
    // Toda a autenticação (token) e a chamada ao /gerar ficam por conta da DLL
    // oficial; esta ponte só chama GerarCIOT e devolve o resultado.
    //
    // Uso:    GeradorCIOTPonte.exe <cpfCnpj>
    // Saída:  última linha "CIOT=<12 dígitos>" (sucesso) ou "ERRO=<mensagem>".
    //         Outras linhas são mensagens da própria DLL da ANTT.
    // Código: 0 = sucesso, 1 = falha, 2 = uso incorreto.
    internal static class Program
    {
        private static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);

            // Compilado pelo csc sem atributo de versão, o .NET assume o padrão antigo
            // (só SSL3 e TLS 1.0). O gerador de produção da ANTT (API Gateway da AWS)
            // recusa: "Não foi possível criar um canal seguro para SSL/TLS".
            // A homologação aceita TLS 1.0, por isso lá funcionava.
            ServicePointManager.SecurityProtocol =
                SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

            if (args.Length != 1 || args[0].Trim().Length == 0)
            {
                Console.WriteLine("ERRO=Uso: GeradorCIOTPonte.exe <cpfCnpj>");
                return 2;
            }

            string cpfCnpj = args[0].Trim();
            try
            {
                var servico = new GeradorCIOTShared.GeradorCIOTService_v3();
                string retorno = servico.GerarCIOT(cpfCnpj);
                string ciot = (retorno ?? "").Trim();

                if (EhCiotValido(ciot))
                {
                    Console.WriteLine("CIOT=" + ciot);
                    return 0;
                }

                Console.WriteLine("ERRO=" + UmaLinha(retorno));
                return 1;
            }
            catch (Exception ex)
            {
                Exception interna = ex;
                while (interna.InnerException != null)
                    interna = interna.InnerException;
                Console.WriteLine("ERRO=" + UmaLinha(ex.GetType().Name + ": " + interna.Message));
                return 1;
            }
        }

        private static bool EhCiotValido(string s)
        {
            if (s.Length != 12)
                return false;
            foreach (char c in s)
                if (c < '0' || c > '9')
                    return false;
            return true;
        }

        private static string UmaLinha(string s)
        {
            if (string.IsNullOrEmpty(s))
                return "(a DLL da ANTT nao devolveu nada)";
            return s.Replace("\r", " ").Replace("\n", " ").Trim();
        }
    }
}
