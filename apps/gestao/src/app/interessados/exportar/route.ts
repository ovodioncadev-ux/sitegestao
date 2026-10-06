import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { celulaCsv } from '@/lib/csv';

export const dynamic = 'force-dynamic';

type Linha = {
  nome: string | null;
  telefone: string | null;
  email: string | null;
  cep: string;
  origem: string;
  status: string;
  area_atendida_em: string | null;
  criado_em: string;
};

/** Só o dono baixa. Dado pessoal: nunca em cache. */
export async function GET() {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return new Response('Sem permissão.', { status: 403 });

  const linhas = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Linha>(
      `select nome, telefone, email, cep, origem, status, area_atendida_em::text, criado_em::text
         from interessados order by criado_em desc limit 5000`,
    ),
  );

  const cabecalho = ['Nome', 'Telefone', 'E-mail', 'CEP', 'Origem', 'Situação', 'Área atendida em', 'Pediu em'];
  const corpo = linhas.map((l) =>
    [l.nome, l.telefone, l.email, l.cep, l.origem, l.status, l.area_atendida_em, l.criado_em].map(celulaCsv).join(','),
  );
  const csv = '﻿' + [cabecalho.map(celulaCsv).join(','), ...corpo].join('\r\n') + '\r\n';

  return new Response(csv, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': 'attachment; filename="interessados.csv"',
      'Cache-Control': 'no-store',
    },
  });
}
