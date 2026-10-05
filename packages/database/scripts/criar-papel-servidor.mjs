#!/usr/bin/env node
/**
 * Cria (ou atualiza a senha do) papel de login `app_servidor`.
 *
 * Roda UMA vez por banco, com a conexão administrativa, e depois sempre que
 * a senha for rotacionada.
 *
 *   pnpm --filter @ovo/database db:papel-servidor
 *
 * Por que isto não está numa migration: migration vai para o Git, e senha
 * não vai para o Git. A senha vem do .env, que o .gitignore bloqueia.
 *
 * O que este papel PODE: virar app_anon e app_usuario.
 * O que ele NÃO PODE: virar a dona das tabelas. É essa fronteira que
 * separa "o app" de "o administrador", e é a mesma fronteira que a chave
 * anon e a service_role faziam no Supabase.
 */

import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = resolve(aqui, '../../..');

for (const arquivo of ['.env', '.env.local']) {
  const caminho = resolve(raiz, arquivo);
  if (!existsSync(caminho)) continue;
  for (const linha of readFileSync(caminho, 'utf8').split('\n')) {
    const m = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    if (!(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}

const urlAdmin = process.env.DATABASE_ADMIN_URL;
const senha = process.env.APP_SERVIDOR_SENHA;

if (!urlAdmin || !senha) {
  console.error(
    'Faltam variáveis. Preencha DATABASE_ADMIN_URL e APP_SERVIDOR_SENHA no .env da raiz.',
  );
  process.exit(1);
}

if (senha.length < 20) {
  console.error('APP_SERVIDOR_SENHA precisa ter ao menos 20 caracteres. Gere uma aleatória.');
  process.exit(1);
}

const cliente = new pg.Client({ connectionString: urlAdmin });

try {
  await cliente.connect();

  // A senha entra como literal escapado pelo próprio Postgres (quote_literal),
  // e não por concatenação de string nossa.
  //
  // Duas armadilhas encontradas rodando isto contra um Neon de verdade:
  //
  // 1. Não dá para mandar a senha como parâmetro ($1) direto no
  //    `do $$ ... $$`: o texto entre os `$$` é uma string dollar-quoted, e
  //    o Postgres não olha dentro dela procurando parâmetro — ele prepara
  //    a instrução com ZERO parâmetros esperados, e o driver que manda um
  //    dá "bind message supplies 1 parameters, but prepared statement
  //    requires 0". Por isso o escape acontece numa consulta separada
  //    primeiro, com `select quote_literal($1::text)`.
  //
  // 2. O proxy do Neon intercepta `alter/create role ... password` para
  //    sincronizar com o control plane dele, e essa interceptação exige a
  //    senha como um literal único e direto — `'...' || '...'` confunde o
  //    parser dele e corrompe a instrução (erro de sintaxe apontando para
  //    o meio da senha). Por isso o literal já escapado por quote_literal
  //    entra aninhado dentro da string do `execute` (aspas simples
  //    dobradas de novo, para valer como uma string só), nunca por
  //    concatenação.
  const { rows: escapadas } = await cliente.query('select quote_literal($1::text) as literal', [
    senha,
  ]);
  const senhaParaExecute = escapadas[0].literal.replace(/'/g, "''");

  await cliente.query(
    `do $$
     begin
       if exists (select 1 from pg_roles where rolname = 'app_servidor') then
         execute 'alter role app_servidor with login noinherit password ${senhaParaExecute}';
       else
         execute 'create role app_servidor with login noinherit password ${senhaParaExecute}';
       end if;
     end;
     $$;`,
  );

  // `with inherit false` é o que faz o papel NÃO carregar os privilégios de
  // app_usuario sem pedir. Sem isso, esquecer o `set local role` numa rota
  // devolveria lista vazia em silêncio — que parece "não há dados" e esconde
  // o erro. Com isso, dá "permission denied", que grita.
  //
  // Atenção: `alter role ... noinherit` sozinho NÃO resolve. No Postgres 16
  // a herança é gravada em cada concessão, e mexer no papel só muda o padrão
  // das concessões FUTURAS. Por isso o `with inherit false` vem aqui, na
  // própria concessão, e é reaplicado toda vez que este script roda.
  await cliente.query('grant app_anon, app_usuario to app_servidor with inherit false');
  await cliente.query('grant connect on database ' + (await nomeDoBanco(cliente)) + ' to app_servidor');

  // `rolname` é do tipo `name`, e `array_agg` sobre `name` sai como `name[]`
  // — um tipo de catálogo que o driver `pg` não sabe parsear como array (vem
  // como texto crú, "{a,b}"). O cast para `text[]` resolve.
  const { rows } = await cliente.query(`
    select r.rolname as papel,
           coalesce(array_agg(m.rolname::text) filter (where m.rolname is not null), '{}'::text[]) as membro_de
    from pg_roles r
    left join pg_auth_members am on am.member = r.oid
    left join pg_roles m on m.oid = am.roleid
    where r.rolname = 'app_servidor'
    group by r.rolname
  `);

  console.log('');
  console.log('✔ app_servidor pronto.');
  console.log(`  membro de: ${rows[0]?.membro_de?.join(', ') ?? '(nenhum)'}`);
  console.log('');
  console.log('  Agora monte a DATABASE_URL trocando o usuário e a senha da');
  console.log('  DATABASE_ADMIN_URL por app_servidor e esta senha.');
  console.log('');
} catch (erro) {
  console.error(`✘ ${erro.message}`);
  process.exitCode = 1;
} finally {
  await cliente.end().catch(() => {});
}

async function nomeDoBanco(c) {
  const { rows } = await c.query('select current_database() as nome');
  return `"${rows[0].nome.replace(/"/g, '""')}"`;
}
