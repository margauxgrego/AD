// Vercel serverless function — Supabase keep-alive
// Appelée par GitHub Actions chaque semaine pour éviter la mise en pause Supabase free tier.
// Lecture seule : SELECT id FROM imports LIMIT 1 via REST API.
// Toute réponse HTTP de Supabase (y compris 401/403 RLS) = projet actif.

const SUPABASE_URL = "https://awamnjpfnacobfbbtqwl.supabase.co";
const SUPABASE_KEY = "sb_publishable_-sntcHXCOiWtkgzMg6o-aA_Wt_8nPQK";

module.exports = async function handler(req, res) {
  try {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/imports?select=id&limit=1`,
      {
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
        },
      }
    );
    // Tout code < 500 signifie que Supabase a répondu = projet actif
    const alive = r.status < 500;
    return res.status(alive ? 200 : 502).json({
      ok: alive,
      supabase_status: r.status,
      ts: new Date().toISOString(),
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: e.message });
  }
};
