"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Eye,
  EyeOff,
  Lock,
  Mail,
  ShieldCheck,
  AlertCircle,
  CheckCircle2,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const erroUrl = searchParams.get("erro");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(
    erroUrl === "conta_desativada"
      ? "Sua conta está desativada. Procure a Tesouraria da Atlética."
      : erroUrl === "link_recuperacao_invalido"
      ? "O link de recuperação expirou ou é inválido. Solicite um novo link ou peça o reset à Tesouraria."
      : null
  );

  // Estado do modal "Esqueci minha senha" (Opção 3.2)
  const [resetDialogOpen, setResetDialogOpen] = useState(false);
  const [resetEmail, setResetEmail] = useState("");
  const [resetLoading, setResetLoading] = useState(false);
  const [resetSuccess, setResetSuccess] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setErrorMsg(null);
    setLoading(true);

    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (error || !data.user) {
      setErrorMsg("E-mail ou senha incorretos. Verifique os dados informados.");
      setLoading(false);
      return;
    }

    // Busca o perfil para redirecionar conforme a regra 2A
    const { data: perfil } = await supabase
      .from("perfis")
      .select("role, precisa_trocar_senha, ativo")
      .eq("id", data.user.id)
      .single();

    if (perfil && !perfil.ativo) {
      await supabase.auth.signOut();
      setErrorMsg(
        "Sua conta está desativada. Entre em contato com a Tesouraria."
      );
      setLoading(false);
      return;
    }

    if (perfil?.precisa_trocar_senha) {
      router.push("/primeiro-acesso");
    } else if (perfil?.role === "admin") {
      router.push("/admin");
    } else {
      router.push("/aluno");
    }
    router.refresh();
  }

  async function handleSendRecoveryEmail(e: React.FormEvent) {
    e.preventDefault();
    setResetError(null);
    setResetSuccess(false);
    setResetLoading(true);

    const supabase = createClient();
    const redirectTo = `${window.location.origin}/auth/callback?next=/redefinir-senha`;

    const { error } = await supabase.auth.resetPasswordForEmail(
      resetEmail.trim(),
      { redirectTo }
    );

    setResetLoading(false);

    if (error) {
      setResetError(
        "Não foi possível enviar o e-mail no momento. Você também pode pedir uma nova senha provisória diretamente ao Tesoureiro pelo WhatsApp."
      );
      return;
    }

    setResetSuccess(true);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4 py-8">
      <Card className="w-full max-w-md border-slate-200 shadow-md">
        <CardHeader className="space-y-2 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
            <ShieldCheck className="h-6 w-6" />
          </div>
          <CardTitle className="text-2xl font-bold text-slate-900">
            Atlética Medicina
          </CardTitle>
          <CardDescription>
            Controle de Pagamentos e Mensalidades
          </CardDescription>
        </CardHeader>

        <CardContent>
          <form onSubmit={handleLogin} className="space-y-4">
            {errorMsg && (
              <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                <span>{errorMsg}</span>
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="email">E-mail</Label>
              <div className="relative">
                <Mail className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <Input
                  id="email"
                  type="email"
                  placeholder="seu.email@exemplo.com"
                  className="pl-9"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  autoComplete="email"
                />
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="password">Senha</Label>
                <Dialog
                  open={resetDialogOpen}
                  onOpenChange={(open) => {
                    setResetDialogOpen(open);
                    if (open && email) setResetEmail(email);
                    setResetError(null);
                    setResetSuccess(false);
                  }}
                >
                  <DialogTrigger asChild>
                    <button
                      type="button"
                      className="text-xs font-medium text-emerald-700 hover:underline"
                    >
                      Esqueci minha senha?
                    </button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Recuperação de Senha</DialogTitle>
                      <DialogDescription>
                        Informe seu e-mail cadastrado para receber um link de
                        redefinição ou solicite uma nova senha provisória à
                        Tesouraria.
                      </DialogDescription>
                    </DialogHeader>

                    {resetSuccess ? (
                      <div className="space-y-3 rounded-lg border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
                        <div className="flex items-center gap-2 font-semibold">
                          <CheckCircle2 className="h-4 w-4" />
                          <span>E-mail de recuperação enviado!</span>
                        </div>
                        <p>
                          Verifique sua caixa de entrada e a pasta de Spam. Caso
                          não receba em alguns minutos, peça ao Tesoureiro da
                          Atlética para clicar em{" "}
                          <strong>&ldquo;Resetar Senha Provisória&rdquo;</strong>{" "}
                          e te enviar pelo WhatsApp.
                        </p>
                      </div>
                    ) : (
                      <form
                        onSubmit={handleSendRecoveryEmail}
                        className="space-y-4"
                      >
                        {resetError && (
                          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                            {resetError}
                          </div>
                        )}
                        <div className="space-y-2">
                          <Label htmlFor="reset-email">Seu e-mail</Label>
                          <Input
                            id="reset-email"
                            type="email"
                            placeholder="seu.email@exemplo.com"
                            value={resetEmail}
                            onChange={(e) => setResetEmail(e.target.value)}
                            required
                          />
                        </div>
                        <div className="rounded-lg bg-slate-100 p-3 text-xs text-slate-600">
                          <strong>Dica rápida:</strong> Se preferir, você também
                          pode chamar a Tesouraria no WhatsApp e solicitar uma
                          nova senha provisória instantânea.
                        </div>
                        <DialogFooter>
                          <Button
                            type="submit"
                            className="w-full"
                            disabled={resetLoading}
                          >
                            {resetLoading
                              ? "Enviando link..."
                              : "Enviar link por e-mail"}
                          </Button>
                        </DialogFooter>
                      </form>
                    )}
                  </DialogContent>
                </Dialog>
              </div>

              <div className="relative">
                <Lock className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••••••"
                  className="pl-9 pr-10"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
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

            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? "Entrando..." : "Entrar no Sistema"}
            </Button>
          </form>
        </CardContent>

        <CardFooter className="justify-center border-t border-slate-100 pt-4 text-center text-xs text-slate-500">
          Acesso exclusivo para membros e diretoria da Atlética.
        </CardFooter>
      </Card>
    </div>
  );
}

