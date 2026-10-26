import { redirect } from "next/navigation";
import { UserCheck } from "lucide-react";
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

export default async function AlunoHomePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: perfil } = await supabase
    .from("perfis")
    .select("nome_completo, email, matricula_ou_turma, saldo_credito")
    .eq("id", user.id)
    .single();

  const saldo = Number(perfil?.saldo_credito ?? 0);

  return (
    <div className="min-h-screen bg-slate-50">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-4xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
              <UserCheck className="h-5 w-5" />
            </div>
            <div>
              <h1 className="text-base font-bold text-slate-900">
                Portal do Aluno — Atlética Medicina
              </h1>
              <p className="text-xs text-slate-500">
                {perfil?.nome_completo}
                {perfil?.matricula_ou_turma
                  ? ` • ${perfil.matricula_ou_turma}`
                  : ""}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <Badge variant="secondary">Membro</Badge>
            <LogoutButton />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-4xl space-y-6 px-4 py-8">
        <Card>
          <CardHeader>
            <CardTitle>Meu Saldo na Atlética</CardTitle>
            <CardDescription>
              Créditos acumulados ou saldo pendente de parcelas anteriores
            </CardDescription>
          </CardHeader>
          <CardContent>
            <p
              className={`text-2xl font-bold ${
                saldo < 0
                  ? "text-red-600"
                  : saldo > 0
                  ? "text-emerald-700"
                  : "text-slate-800"
              }`}
            >
              {saldo.toLocaleString("pt-BR", {
                style: "currency",
                currency: "BRL",
              })}
            </p>
          </CardContent>
        </Card>
      </main>
    </div>
  );
}

