"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  CheckCircle2,
  Circle,
  Eye,
  EyeOff,
  KeyRound,
  AlertCircle,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { evaluatePasswordStrength } from "@/features/auth/validations/password";
import { LogoutButton } from "@/features/auth/components/logout-button";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export function PrimeiroAcessoForm() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const checks = evaluatePasswordStrength(password, confirmPassword);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!checks.isValid) return;

    setErrorMsg(null);
    setLoading(true);

    const supabase = createClient();

    // 1. Atualiza a senha no Supabase Auth
    const { error: updateAuthError } = await supabase.auth.updateUser({
      password,
    });

    if (updateAuthError) {
      setErrorMsg(
        updateAuthError.message.includes("different from the old password")
          ? "A nova senha deve ser diferente da senha provisória."
          : "Não foi possível atualizar a senha. Tente uma senha diferente da provisória."
      );
      setLoading(false);
      return;
    }

    // 2. Marca precisa_trocar_senha = false no banco via função RPC segura
    const { error: rpcError } = await supabase.rpc("marcar_senha_trocada");

    if (rpcError) {
      setErrorMsg(
        "Sua senha foi alterada, mas houve um erro ao concluir o primeiro acesso. Tente novamente."
      );
      setLoading(false);
      return;
    }

    // 3. Redireciona para o painel correspondente ao perfil
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      const { data: perfil } = await supabase
        .from("perfis")
        .select("role")
        .eq("id", user.id)
        .single();

      router.push(perfil?.role === "admin" ? "/admin" : "/aluno");
      router.refresh();
    } else {
      router.push("/login");
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4 py-8">
      <Card className="w-full max-w-md border-slate-200 shadow-md">
        <CardHeader className="space-y-2 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-amber-100 text-amber-700">
            <KeyRound className="h-6 w-6" />
          </div>
          <CardTitle className="text-xl font-bold text-slate-900">
            Primeiro Acesso — Troca Obrigatória
          </CardTitle>
          <CardDescription>
            Por segurança, substitua sua senha provisória por uma senha pessoal
            forte antes de acessar o sistema.
          </CardDescription>
        </CardHeader>

        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {errorMsg && (
              <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                <span>{errorMsg}</span>
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="nova-senha">Nova Senha</Label>
              <div className="relative">
                <Input
                  id="nova-senha"
                  type={showPassword ? "text" : "password"}
                  placeholder="Crie sua nova senha"
                  className="pr-10"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="new-password"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((prev) => !prev)}
                  className="absolute right-3 top-2.5 text-slate-400 hover:text-slate-600"
                  tabIndex={-1}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
            </div>

            <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
              <p className="font-semibold text-slate-700 mb-1">
                Requisitos de segurança da senha:
              </p>
              <RequirementItem
                met={checks.minLength}
                label="Mínimo de 8 caracteres"
              />
              <RequirementItem
                met={checks.hasUppercase && checks.hasLowercase}
                label="Pelo menos 1 letra maiúscula e 1 minúscula"
              />
              <RequirementItem
                met={checks.hasNumber}
                label="Pelo menos 1 número (0-9)"
              />
              <RequirementItem
                met={checks.hasSymbol}
                label="Pelo menos 1 símbolo especial (!@#$%&*)"
              />
              <RequirementItem
                met={checks.matchesConfirmation}
                label="Confirmação idêntica à nova senha"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="confirmar-senha">Confirmar Nova Senha</Label>
              <Input
                id="confirmar-senha"
                type={showPassword ? "text" : "password"}
                placeholder="Digite a nova senha novamente"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                autoComplete="new-password"
              />
            </div>

            <Button
              type="submit"
              className="w-full"
              disabled={!checks.isValid || loading}
            >
              {loading ? "Salvando senha..." : "Salvar Senha e Continuar"}
            </Button>
          </form>
        </CardContent>

        <CardFooter className="justify-between border-t border-slate-100 pt-4">
          <span className="text-xs text-slate-500">Deseja usar outra conta?</span>
          <LogoutButton />
        </CardFooter>
      </Card>
    </div>
  );
}

function RequirementItem({ met, label }: { met: boolean; label: string }) {
  return (
    <div
      className={`flex items-center gap-2 ${
        met ? "text-emerald-700 font-medium" : "text-slate-500"
      }`}
    >
      {met ? (
        <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-600" />
      ) : (
        <Circle className="h-3.5 w-3.5 shrink-0 text-slate-400" />
      )}
      <span>{label}</span>
    </div>
  );
}

