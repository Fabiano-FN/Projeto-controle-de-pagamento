import { redirect } from "next/navigation";
import { ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { LogoutButton } from "@/features/auth/components/logout-button";

export default async function AdminHomePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: perfil } = await supabase
    .from("perfis")
    .select("nome_completo, email, role")
    .eq("id", user.id)
    .single();

  return (
    <div className="min-h-screen bg-slate-50">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <div>
              <h1 className="text-base font-bold text-slate-900">
                Painel da Tesouraria
              </h1>
              <p className="text-xs text-slate-500">
                {perfil?.nome_completo} ({perfil?.email})
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <Badge variant="success">Tesoureiro (Admin)</Badge>
            <LogoutButton />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-8">
        <Card>
          <CardHeader>
            <CardTitle>Autenticação e Controle de Acesso Concluídos</CardTitle>
            <CardDescription>
              Você está autenticado na rota protegida <code>/admin</code>. Na
              Fase 2 adicionaremos aqui o cadastro de alunos, lançamento de
              parcelas em lote e configuração da Chave PIX.
            </CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-slate-600">
            Sessão ativa para <strong>{perfil?.nome_completo}</strong>.
          </CardContent>
        </Card>
      </main>
    </div>
  );
}

