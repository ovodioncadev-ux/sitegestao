import 'server-only';

import { betterAuth } from 'better-auth';
import { Pool } from 'pg';
import { exigirEnv, envOpcional } from '../env';
import { OCIOSIDADE_CONEXAO_MS, ouvirErrosDoPool } from '../acesso';
import { emailConfigurado, enviarEmail } from '../email';
import { criarArmazenamentoDeLimite } from './rate-limit-storage';

/**
 * ═══════════════════════════════════════════════════════════════════════
 * Autenticação.
 *
 * O Better Auth fala com o banco pela conexão ADMINISTRATIVA, porque ele
 * precisa escrever nas quatro tabelas que guardam hash de senha e token de
 * sessão — as mesmas que nenhum papel de aplicação alcança.
 *
 * Duas formas de entrar, de propósito:
 *
 *   • Google — para quem tem conta Google e não quer inventar mais uma senha
 *   • e-mail e senha — para quem não tem, e para o app de produção da granja
 *
 * O vínculo entre as duas é por e-mail, e só é aceito vindo do Google,
 * porque o Google confirma o endereço. Aceitar vínculo automático de um
 * provedor que NÃO confirma e-mail é como entregar a conta para quem
 * cadastrar o endereço primeiro.
 *
 * Confira os nomes de opção contra a documentação da versão instalada
 * sempre que atualizar a biblioteca.
 * ═══════════════════════════════════════════════════════════════════════
 */

const googleId = envOpcional('GOOGLE_CLIENT_ID');
const googleSecret = envOpcional('GOOGLE_CLIENT_SECRET');

/** Só monta o provedor quando as duas variáveis existem. Meia configuração quebra o login inteiro. */
const provedoresSociais = googleId && googleSecret
  ? { google: { clientId: googleId, clientSecret: googleSecret } }
  : {};

const poolAuth = ouvirErrosDoPool(
  new Pool({
    connectionString: exigirEnv('DATABASE_ADMIN_URL'),
    max: 4,
    // Toda página logada começa lendo a sessão por aqui; o padrão do pg
    // (10 s) fazia quase todo clique reabrir a conexão. Ver acesso.ts.
    idleTimeoutMillis: OCIOSIDADE_CONEXAO_MS,
    keepAlive: true,
  }),
  'auth',
);

export const auth = betterAuth({
  database: poolAuth,

  baseURL: exigirEnv('BETTER_AUTH_URL'),
  secret: exigirEnv('BETTER_AUTH_SECRET'),

  emailAndPassword: {
    enabled: true,
    minPasswordLength: 12,
    // Só exige confirmação quando existe serviço de e-mail para enviá-la.
    // Sem ele, exigir trancaria todo mundo do lado de fora. Enquanto não
    // houver, o e-mail da conta NÃO é confirmado — e por isso o banco só
    // vincula conta a cliente pré-existente por e-mail quando
    // "emailVerified" é true (migration 13).
    requireEmailVerification: emailConfigurado,
  },

  emailVerification: {
    sendOnSignUp: emailConfigurado,
    autoSignInAfterVerification: true,
    sendVerificationEmail: async ({ user, url }) => {
      // Sem await: não deixa o tempo de resposta revelar se o e-mail existe.
      void enviarEmail({
        para: user.email,
        assunto: 'Confirme seu e-mail — Ovo di Onça',
        texto: [
          `Olá, ${user.name}.`,
          '',
          'Confirme seu e-mail para ativar sua conta na Ovo di Onça:',
          url,
          '',
          'Se você não criou esta conta, ignore esta mensagem.',
        ].join('\n'),
      }).catch((erro: unknown) => console.error('[e-mail de confirmação]', erro instanceof Error ? erro.message : erro));
    },
  },

  socialProviders: provedoresSociais,

  // Rate limit por IP. Login e cadastro são as portas que aceitam tentativa em
  // série (chute de senha, criação de conta em massa), então têm limite próprio
  // e bem mais baixo que o geral. Vale para os dois apps: usam este mesmo auth().
  //
  // O contador mora no Postgres (consumir_rate_limit, migration do Bloco 8): vale entre
  // todas as instâncias, não só dentro de um processo, e sobrevive a reinício.
  rateLimit: {
    enabled: true,
    window: 60,
    max: 100,
    customRules: {
      '/sign-in/email': { window: 60, max: 5 },
      '/sign-up/email': { window: 3600, max: 5 },
    },
    customStorage: criarArmazenamentoDeLimite((sql, parametros) => poolAuth.query(sql, parametros)),
  },

  account: {
    accountLinking: {
      enabled: true,
      // Só o Google. Ele confirma o e-mail; provedor que não confirma não entra aqui.
      trustedProviders: ['google'],
    },
  },

  session: {
    expiresIn: 60 * 60 * 24 * 7,   // 7 dias
    updateAge: 60 * 60 * 24,       // renova a cada 24h de uso
  },

  advanced: {
    defaultCookieAttributes: {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
    },
  },

  // Este auth() é compartilhado pelos dois apps (cada um monta sua própria
  // rota /api/auth contra o mesmo banco) — por isso as duas origens, não só
  // a de BETTER_AUTH_URL. Sem a origem certa aqui, o Better Auth recusa a
  // requisição com "Invalid origin" antes de checar e-mail ou senha; o
  // curl não mostra esse erro porque não manda cabeçalho Origin, só o
  // navegador manda.
  trustedOrigins: [
    exigirEnv('BETTER_AUTH_URL'),
    envOpcional('NEXT_PUBLIC_URL_GESTAO'),
    envOpcional('NEXT_PUBLIC_URL_ASSINANTE'),
  ].filter((origem): origem is string => Boolean(origem)),
});

/** A conta só entra depois de confirmar o e-mail? (Só quando há serviço de e-mail.) */
export const confirmacaoDeEmailAtiva = emailConfigurado;

/** O Google está configurado neste ambiente? A tela usa isto para mostrar ou não o botão. */
export const loginComGoogleDisponivel = Boolean(googleId && googleSecret);

export type Sessao = typeof auth.$Infer.Session;
