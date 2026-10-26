import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(
          cookiesToSet: {
            name: string;
            value: string;
            options: CookieOptions;
          }[]
        ) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          supabaseResponse = NextResponse.next({
            request,
          });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const pathname = request.nextUrl.pathname;
  const isAuthCallback = pathname.startsWith("/auth/callback");
  const isResetPassword = pathname.startsWith("/redefinir-senha");
  const isLoginPage = pathname.startsWith("/login");
  const isFirstAccessPage = pathname.startsWith("/primeiro-acesso");

  // Libera a rota de callback de autenticação
  if (isAuthCallback) {
    return supabaseResponse;
  }

  // Se não está logado, redireciona qualquer rota protegida para /login
  if (!user) {
    if (!isLoginPage) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      return NextResponse.redirect(url);
    }
    return supabaseResponse;
  }

  // Usuário autenticado: busca o perfil no banco para verificar role, ativo e precisa_trocar_senha
  const { data: perfil } = await supabase
    .from("perfis")
    .select("role, precisa_trocar_senha, ativo")
    .eq("id", user.id)
    .single();

  // Caso o usuário esteja desativado (ativo = false), encerra a sessão e redireciona para /login
  if (perfil && !perfil.ativo) {
    await supabase.auth.signOut();
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("erro", "conta_desativada");
    return NextResponse.redirect(url);
  }

  const role = perfil?.role ?? "aluno";
  const precisaTrocarSenha = perfil?.precisa_trocar_senha ?? true;
  const destinoPadrao = role === "admin" ? "/admin" : "/aluno";

  // Permite que o usuário vindo do link de recuperação de e-mail acesse /redefinir-senha
  if (isResetPassword) {
    return supabaseResponse;
  }

  // Regra obrigatória do 1º acesso: se precisa_trocar_senha == true, força ir para /primeiro-acesso
  if (precisaTrocarSenha && !isFirstAccessPage) {
    const url = request.nextUrl.clone();
    url.pathname = "/primeiro-acesso";
    return NextResponse.redirect(url);
  }

  // Se já trocou a senha e tentar acessar /primeiro-acesso, /login ou /, envia ao painel do seu perfil
  if (
    !precisaTrocarSenha &&
    (isFirstAccessPage || isLoginPage || pathname === "/")
  ) {
    const url = request.nextUrl.clone();
    url.pathname = destinoPadrao;
    return NextResponse.redirect(url);
  }

  // Proteção RBAC entre perfis: aluno não acessa /admin e admin tem rota própria
  if (pathname.startsWith("/admin") && role !== "admin") {
    const url = request.nextUrl.clone();
    url.pathname = "/aluno";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}

