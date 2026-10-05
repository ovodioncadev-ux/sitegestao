#!/usr/bin/env node
/**
 * Aplica (ou reverte) as migrations SÓ no banco de testes.
 *
 *   pnpm db:migrar:teste            # up (todas as pendentes)
 *   pnpm db:migrar:teste down       # reverte a última
 *
 * Passa pelo mesmo guarda dos testes: sem DATABASE_TEST_URL, ou com ela igual
 * ao banco principal, aborta antes de conectar. O banco principal só é
 * migrado por `pnpm db:migrar`, de propósito e à mão.
 */

import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { urlDoBancoDeTeste } from './banco-teste.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const url = urlDoBancoDeTeste();

const direcao = process.argv[2] === 'down' ? 'down' : 'up';
const extras = process.argv.slice(direcao === process.argv[2] ? 3 : 2);

// A variável repassada ao migrador se chama DATABASE_URL só dentro deste
// processo filho; o .env não é lido por ele (sem --envPath).
const filho = spawnSync(
  process.execPath,
  [
    resolve(aqui, '../node_modules/node-pg-migrate/bin/node-pg-migrate.js'),
    direcao,
    ...extras,
    '-m',
    resolve(aqui, '../migrations'),
  ],
  { stdio: 'inherit', env: { ...process.env, DATABASE_URL: url } },
);
process.exit(filho.status ?? 1);
