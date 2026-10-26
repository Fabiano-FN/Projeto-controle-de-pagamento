import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Atlética Medicina — Controle de Pagamentos",
  description:
    "Sistema de controle de mensalidades, pagamentos via PIX e comprovantes da Atlética de Medicina.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body className="min-h-screen bg-slate-50 text-slate-900">
        {children}
      </body>
    </html>
  );
}

