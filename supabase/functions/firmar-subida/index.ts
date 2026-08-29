// Firma de subida a Cloudinary.
//
// Por qué existe: un "unsigned upload preset" deja que cualquiera con el nombre
// del cloud suba archivos a tu cuenta hasta agotarla. Aquí el api_secret no sale
// nunca del servidor: se comprueba que hay sesión, se devuelve una firma atada a
// la carpeta de ESE negocio, y el navegador sube directo a Cloudinary con ella.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME')!
const API_KEY    = Deno.env.get('CLOUDINARY_API_KEY')!
const API_SECRET = Deno.env.get('CLOUDINARY_API_SECRET')!

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })

async function sha1(texto: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(texto))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  const auth = req.headers.get('Authorization')
  if (!auth) return json({ error: 'Falta la sesión' }, 401)

  // Cliente con el JWT del usuario: RLS decide, no nosotros.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return json({ error: 'Sesión inválida' }, 401)

  const { data: negocioId, error } = await supabase.rpc('auth_negocio_id')
  if (error || !negocioId) return json({ error: 'Esta cuenta no tiene negocio' }, 403)

  // La carpeta la fija el servidor. Si viniera del cliente, un negocio podría
  // escribir en la carpeta de otro.
  const folder = `ventasroma/${negocioId}`
  const timestamp = Math.floor(Date.now() / 1000)

  // Cloudinary firma los parámetros ordenados alfabéticamente: folder, timestamp.
  const signature = await sha1(`folder=${folder}&timestamp=${timestamp}${API_SECRET}`)

  return json({
    cloudName: CLOUD_NAME,
    apiKey: API_KEY,
    timestamp,
    folder,
    signature,
    uploadUrl: `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`,
  })
})
