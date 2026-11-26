// Tra ve so lieu da gop san duoi dang CSV cho Google Sheets doc bang IMPORTDATA.
// Goi: https://<project>.supabase.co/functions/v1/bao-cao?khoa=<KHOA>&bang=gop_rong
//
// Noi thang vao Postgres bang SUPABASE_DB_URL thay vi qua PostgREST, de khong
// vuong chuyen phan quyen vai anon / service_role.
//
// Cai dat kem theo:
//   - Edge Function Secrets: KHOA_BAO_CAO
//   - Settings cua ham: tat "Verify JWT" (IMPORTDATA khong gui duoc header)
//   - Trong Google Sheets: bam "Cho phep truy cap" lan dau cho ca file

import postgres from 'npm:postgres@3.4.4';

const CHO_PHEP = [
  'gop_rong', 'gop_khach_ngay', 'gop_booking',
  'gop_tag_ngay', 'gop_content', 'gop_ads', 'nhat_ky_chay', 'sao_luu_ngay',
];

function sangCsv(hang: Record<string, unknown>[]): string {
  if (!hang.length) return '';
  const cot = Object.keys(hang[0]);
  const o = (v: unknown) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\n]/.test(s) ? '"' + s.replaceAll('"', '""') + '"' : s;
  };
  const dong = [cot.join(',')];
  for (const h of hang) dong.push(cot.map((c) => o(h[c])).join(','));
  return dong.join('\n');
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (url.searchParams.get('khoa') !== Deno.env.get('KHOA_BAO_CAO')) {
    return new Response('Sai khoa', { status: 401 });
  }
  const bang = url.searchParams.get('bang') ?? 'gop_rong';

  if (bang === 'chan_doan') {
    const ten = Object.keys(Deno.env.toObject())
      .filter((k) => k.startsWith('SUPABASE') || k.startsWith('KHOA'))
      .sort().join('\n');
    return new Response(ten, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }

  if (!CHO_PHEP.includes(bang)) {
    return new Response('Bang khong hop le: ' + bang, { status: 400 });
  }

  const chuoiNoi = Deno.env.get('SUPABASE_DB_URL');
  if (!chuoiNoi) return new Response('Thieu SUPABASE_DB_URL', { status: 500 });

  const sql = postgres(chuoiNoi, { prepare: false, max: 1 });
  try {
    const hang = await sql.unsafe('select * from ' + bang + ' limit 50000');
    return new Response(sangCsv(hang as unknown as Record<string, unknown>[]), {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    });
  } catch (e) {
    return new Response('Loi: ' + (e as Error).message, { status: 500 });
  } finally {
    await sql.end();
  }
});
