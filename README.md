# Sistema de gestão — Ovo di Onça

Monorepo dos dois apps que rodam sobre um banco só: painel do dono e área do
assinante. A landing page de marketing e o app da granja são outros
repositórios e não entram aqui.

> **Situação: Fase 0 concluída, Fase 1 em andamento.** A fundação de
> segurança e a camada de configuração e clientes estão de pé, testadas
> contra um Postgres de verdade: **25 verificações de comportamento e 5
> estruturais**. **Ainda não existe tela**, e isso é de propósito — um
> sistema bonito que deixa um assinante ler a base de clientes inteira é
> pior do que nenhum sistema.
>
> Já no banco: `perfis`, `config_negocio`, `planos`, `faixas_cep_atendidas`
> e `clientes`. Faltam `entregas`, `faturas`, `saldo_cliente_movimentos` e
> `indicacoes`.

**Stack:** Next.js (App Router) · TypeScript · Tailwind · PostgreSQL puro
(Neon) · Better Auth · monorepo pnpm.

---

## Estrutura

```
sistema/
├── apps/
│   ├── gestao/          painel do dono          → porta 3000
│   └── assinante/       área do cliente         → porta 3001
├── packages/
│   ├── database/        migrations, acesso ao banco, autenticação
│   ├── ui/              tokens de design
│   └── config/          cabeçalhos de segurança dos dois apps
└── scripts/
    └── verificar-segredos.sh
```

---

## Como a autorização funciona

Toda a defesa mora no banco, não na tela. Rota protegida no front-end evita
a tela quebrada; ela não protege o dado.

**Dois papéis de aplicação, nenhum deles com senha:**

| Papel | Quem é | O que alcança |
|---|---|---|
| `app_anon` | visitante sem login | nada, por padrão |
| `app_usuario` | pessoa autenticada | o que a RLS deixar |

**Duas conexões, com senhas diferentes:**

| Variável | Entra como | Para quê |
|---|---|---|
| `DATABASE_URL` | `app_servidor` | o dia a dia. Veste `app_anon` ou `app_usuario` e fica sujeito à RLS |
| `DATABASE_ADMIN_URL` | dona das tabelas | migrations, Better Auth e o caminho administrativo. **Ignora a RLS** |

`app_servidor` **não consegue** virar a dona das tabelas. É essa fronteira
que separa "o app" de "o administrador".

**A cada requisição**, o servidor abre uma transação e, antes de qualquer
consulta, declara quem está falando:

```sql
set local role app_usuario;
set local app.usuario_id = '<id de quem está logado>';
```

No código isso é `comoUsuario(id, bd => ...)` — que manda as duas linhas,
junto com o `begin`, numa ida só ao banco, na forma equivalente
`set_config('role', ..., true)`. O `set local` morre junto com
a transação, então nem com pool de conexão o contexto de um usuário vaza
para a requisição seguinte.

E `app_servidor` recebe os papéis **com `inherit false`**: se alguém
esquecer o `set local role`, o banco responde `permission denied` em vez de
devolver lista vazia. Erro que grita é melhor que erro que se disfarça de
"não há dados".

---

## Rodando pela primeira vez

### 1. Banco no Neon

Crie um projeto em [neon.com](https://neon.com) (plano gratuito). Guarde a
connection string — ela vira `DATABASE_ADMIN_URL`.

### 2. Variáveis

```powershell
copy .env.example .env
notepad .env
```

Preencha `DATABASE_ADMIN_URL`, `APP_SERVIDOR_SENHA` (aleatória, 32
caracteres) e `BETTER_AUTH_SECRET` (idem).

### 3. Migrations e papel de login

```powershell
pnpm install
pnpm db:migrar            # cria as tabelas, os papéis, as policies
pnpm db:papel-servidor    # cria app_servidor com a senha do .env
```

Monte então a `DATABASE_URL` trocando usuário e senha da
`DATABASE_ADMIN_URL` por `app_servidor` e a senha que você gerou.

### Banco de testes (obrigatório para rodar os testes SQL)

Os testes SQL **nunca** rodam no banco principal: sem `DATABASE_TEST_URL` eles
abortam (não há fallback), e também abortam se ela apontar para o mesmo banco
do `DATABASE_URL`/`DATABASE_ADMIN_URL`.

1. No console do Neon, crie um **branch** do projeto (ex.: `teste`) e copie a
   connection string dele (a de dono, como a `DATABASE_ADMIN_URL`).
2. Coloque no `.env` da raiz (o arquivo é ignorado pelo Git):
   `DATABASE_TEST_URL=<connection string do branch>`
3. Aplique as migrations **só nele**: `pnpm db:migrar:teste`
   (`pnpm db:migrar:teste down` reverte a última).
4. Rode `pnpm teste:banco` e `pnpm seguranca`.

Os papéis `app_anon`, `app_usuario` e `app_servidor` pertencem ao projeto Neon e
o branch os herda. Os testes rodam em transação com ROLLBACK, mas o migrador do
teste grava de verdade — por isso só no branch. Manutenção no banco principal
(`db:limpar-teste`) exige o argumento explícito `--banco-principal`, que
arquivos de `tests/` não podem usar.

### 4. Login com Google (opcional, mas recomendado)

No Google Cloud Console → **APIs e serviços** → **Credenciais** → **ID do
cliente OAuth 2.0** → tipo **Aplicativo da Web**.

URIs de redirecionamento autorizados:

```
http://localhost:3001/api/auth/callback/google     (desenvolvimento)
https://SEU-DOMINIO/api/auth/callback/google       (produção)
```

Copie o ID e o segredo para `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET`.
Sem eles, o botão do Google simplesmente não aparece e o login por e-mail e
senha continua funcionando.

---

## Os testes que decidem se a Fase 0 vale

Rode antes de qualquer deploy. Se algum falhar, **não escreva tela**.

```powershell
pnpm seguranca
```

Ele roda três coisas:

| Comando | O que prova |
|---|---|
| `seguranca:segredos` | senha fora do lugar, `.env` versionado ou no histórico, `comoAdmin()` sem checagem de papel |
| `seguranca:estrutura` | policy de update sem `with check`, RLS desligada, função exposta, `search_path` solto, tabela de credencial alcançável |
| `seguranca:autorizacao` | as 15 verificações de comportamento abaixo |

### As 25 verificações de comportamento

**Fundação — papéis e perfis**

| # | Verificação |
|---|---|
| 1 | o perfil nasce como `assinante` — nada vindo do cadastro decide papel |
| 2 | assinante não grava `papel = 'dono'` no próprio perfil |
| 3 | assinante não executa `definir_papel()` |
| 4 | o papel de B continua `assinante` depois das duas tentativas |
| 5–7 | B não lê, não altera e não apaga o perfil de A |
| 8 | **controle positivo** — B altera o próprio nome |
| 9 | sem `app.usuario_id` setado, `app_usuario` não vê nada |
| 10 | `app_anon` não lê a tabela de perfis |
| 11–12 | `app_usuario` não alcança `account` nem `session` — hash de senha e token |
| 13 | `criado_em` é imutável até pela conexão administrativa |
| 14 | **com o grant de coluna afrouxado de propósito, a policy barra sozinha** |
| 15 | **controle positivo** — o dono troca papel por `definir_papel()` |

**Clientes — o teste das duas contas sobre dado de negócio**

| # | Verificação |
|---|---|
| 16 | B não lê o cliente de A |
| 17 | B não altera o cliente de A pela função |
| 18 | ninguém escreve direto em `clientes` — nem o dono |
| 19 | **controle positivo** — B altera o próprio endereço e telefone |
| 20 | `dentro_area_entrega` é calculado do CEP; forçá-lo a `true` não funciona |
| 21 | o código de indicação nasce no formato `ONCA-XXXX`, sem caractere ambíguo |
| 22 | B não rouba o código de indicação de A |
| 23 | `nome_do_indicador()` devolve **só o primeiro nome** |
| 24 | `app_anon` não lê a tabela de clientes |

Os itens 8, 15 e 19 são controles positivos: sem eles, uma conexão errada faz
tudo falhar e o relatório fica verde pelo motivo errado. O item 14 prova que
as três camadas são independentes de verdade, e o 20 prova que um campo
calculado não pode ser forjado pelo corpo da requisição.

---

## Três camadas independentes, não uma

O papel de um usuário está protegido em três alturas, e cada uma segura
sozinha:

1. **Privilégio de coluna** — `app_usuario` só tem `update` em `nome` e
   `telefone`. Não existe privilégio sobre `papel`.
2. **Policy com `with check`** — mesmo com o grant afrouxado, a linha gravada
   precisa manter o papel anterior (verificação 14).
3. **Gatilho `perfis_protege_colunas`** — congela `id` e `criado_em` e recusa
   troca de papel fora do caminho autorizado.

---

## Duas armadilhas encontradas na Fase 0

Ficam registradas porque as duas passam despercebidas e as duas desligam uma
defesa em silêncio.

**1. `alter default privileges in schema public` não funciona para funções.**

O Postgres aceita o comando sem erro, não grava nada em `pg_default_acl`, e a
função criada em seguida continua chamável por `PUBLIC`. A forma que vale é a
do banco inteiro:

```sql
alter default privileges in schema public revoke execute on functions from public;  -- não faz nada
alter default privileges revoke execute on functions from public;                   -- funciona
```

**2. `alter role ... noinherit` não desfaz a herança já concedida.**

No Postgres 16 a herança fica gravada em cada concessão. Mexer no papel só
muda o padrão das concessões futuras. Para valer, o `inherit false` vai na
própria concessão:

```sql
grant app_anon, app_usuario to app_servidor with inherit false;
```

Ambas conferidas no Postgres 16.

---

## Decisões de negócio

As respostas do Fred e da Bruna estão em **[DECISOES.md](DECISOES.md)** — é a
fonte da verdade para frete, desconto, papéis, histórico e o que acontece
quando a entrega falha. Esse arquivo também guarda o que continua em aberto e
duas contradições que precisam de uma segunda palavra antes de virarem código.

Já refletido aqui: o enum `papel_usuario` tem **dois valores, `dono` e
`assinante`** (decidido em 24/09/2026). Não existe `entregador`, e a granja
ficou de fora — ela já tem app próprio.

O que ainda trava a Fase 1: o prazo de frescor por plano, se dúzias continua
sendo produto, e se quinzenal e mensal contam dias ou quartas-feiras. Sem
resposta, **a informação sai do sistema em vez de ser inventada**.

## Próximo passo

**Fase 1 — dados.** Schema completo com RLS na mesma migration que cria cada
tabela, `on delete` decidido em cada chave estrangeira, índices, unicidade, e
o fuso de São Paulo resolvido em toda função que lê "hoje".

Dá para começar pelas tabelas que não dependem do Fred — `clientes`,
`faixas_cep_atendidas`, `config_negocio` — e deixar `planos` por último.
