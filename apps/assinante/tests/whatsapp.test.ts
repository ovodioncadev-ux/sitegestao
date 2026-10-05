import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { WHATSAPP_E164, WHATSAPP_EXIBICAO, WHATSAPP_URL, formatarNacional, urlWhatsapp } from '../../../packages/config/src/whatsapp.mjs';

const RAIZ = resolve(import.meta.dirname, '../../..');
const FONTE_UNICA = join('packages', 'config', 'src', 'whatsapp.mjs');
const FONTE_UNICA_TIPOS = join('packages', 'config', 'src', 'whatsapp.d.mts');
const EXTENSOES = /\.(ts|tsx|mts|mjs|js|jsx|json|css|sql)$/;
// 'tests' e 'migrations': fixtures com telefones fictícios de clientes e histórico do banco, não código de produção.
const IGNORAR = new Set(['node_modules', '.next', '.git', 'dist', 'build', 'out', 'coverage', 'migrations', 'tests']);

/** Comentários não são código executado: um exemplo de telefone num comentário não conta. */
function semComentarios(texto: string): string {
  return texto.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');
}

function arquivos(dir: string): string[] {
  return readdirSync(dir).flatMap((nome) => {
    if (IGNORAR.has(nome)) return [];
    const caminho = join(dir, nome);
    return statSync(caminho).isDirectory() ? arquivos(caminho) : EXTENSOES.test(nome) ? [caminho] : [];
  });
}

const codigo = ['apps', 'packages']
  .flatMap((d) => arquivos(join(RAIZ, d)))
  .filter((f) => {
    const rel = relative(RAIZ, f);
    // A própria fonte e seus tipos podem citar o número; nenhum outro arquivo.
    return rel !== FONTE_UNICA && rel !== FONTE_UNICA_TIPOS;
  });

test('WhatsApp: o número decidido em D12 é a fonte única', () => {
  assert.equal(WHATSAPP_E164, '553125167561');
  assert.equal(WHATSAPP_EXIBICAO, '(31) 2516-7561');
  assert.equal(WHATSAPP_URL, 'https://wa.me/553125167561');
});

test('WhatsApp: texto exibido e link são derivados do mesmo E.164', () => {
  assert.equal(WHATSAPP_URL, `https://wa.me/${WHATSAPP_E164}`);
  assert.equal(WHATSAPP_EXIBICAO, formatarNacional(WHATSAPP_E164));
  assert.equal(formatarNacional('5531999998888'), '(31) 99999-8888'); // celular de 9 dígitos
  assert.equal(urlWhatsapp('Oi, quero assinar'), `${WHATSAPP_URL}?text=Oi%2C%20quero%20assinar`);
});

test('WhatsApp: nenhum arquivo de código tem link wa.me próprio', () => {
  const infratores = codigo.filter((f) => /wa\.me\//.test(readFileSync(f, 'utf8'))).map((f) => relative(RAIZ, f));
  assert.deepEqual(infratores, [], `links wa.me fora da fonte única: ${infratores.join(', ')}`);
});

test('WhatsApp: nenhum arquivo de código tem o número (nem outro número em formato E.164 do Brasil)', () => {
  const padroes = [
    /\b55\d{2}9?\d{8}\b/, // 55 + DDD + número, sem separadores (qualquer telefone, inclusive o "outro" antigo)
    /2516-?7561/,
    /92516/,
  ];
  const infratores = codigo
    .filter((f) => {
      const texto = semComentarios(readFileSync(f, 'utf8'));
      return padroes.some((p) => p.test(texto));
    })
    .map((f) => relative(RAIZ, f));
  assert.deepEqual(infratores, [], `números de telefone escritos fora da fonte única: ${infratores.join(', ')}`);
});

test('WhatsApp: os apps consomem a fonte única', () => {
  const usam = (arquivo: string) => readFileSync(join(RAIZ, arquivo), 'utf8').includes('@ovo/config/whatsapp');
  for (const arquivo of [
    'apps/site/src/components/Footer.tsx',
    'apps/site/src/components/Navbar.tsx',
    'apps/site/src/components/FaqSection.tsx',
    'apps/assinante/src/lib/formatar.ts',
  ]) {
    assert.ok(usam(arquivo), `${arquivo} deveria importar de @ovo/config/whatsapp`);
  }
});
