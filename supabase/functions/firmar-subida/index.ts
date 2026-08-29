// Firma de subida a Cloudinary.
//
// Por qué existe: un "unsigned upload preset" deja que cualquiera con el nombre
// del cloud suba archivos a tu cuenta hasta agotarla. Aquí el api_secret no sale
// nunca del servidor: se comprueba la sesión, se devuelve una firma atada a la
// carpeta de ESE negocio, y el navegador sube directo a Cloudinary con ella.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME')
const API_KEY    = Deno.env.get('CLOUDINARY_API_KEY')
const API_SECRET = Deno.env.get('CLOUDINARY_API_SECRET')

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

// Sin esto, una llamada colgada se come el worker entero y Supabase lo mata con
// un 546 opaco. Mejor fallar en 8s diciendo qué pasó.
function conLimite<T>(p: Promise<T>, ms: number, que: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, rechazar) =>
      setTimeout(() => rechazar(new Error(`tiempo agotado: ${que}`)), ms)),
  ])
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  // Si falta configuración, decirlo claro. Firmar con un secret vacío produce
  // una firma que Cloudinary rechaza con un 401 que no explica nada.
  if (!CLOUD_NAME || !API_KEY || !API_SECRET) {
    const faltan = [
      !CLOUD_NAME && 'CLOUDINARY_CLOUD_NAME',
      !API_KEY && 'CLOUDINARY_API_KEY',
      !API_SECRET && 'CLOUDINARY_API_SECRET',
    ].filter(Boolean).join(', ')
    console.error('faltan secrets:', faltan)
    return json({ error: `Faltan secrets en el servidor: ${faltan}` }, 500)
  }

  const auth = req.headers.get('Authorization')
  if (!auth) return json({ error: 'Falta la sesión' }, 401)

  // Diagnóstico: ?ping=1 pregunta a Cloudinary si el par key/secret es válido,
  // sin revelar el secret. Separa "credenciales mal" de "firma mal construida",
  // que dan el mismo 401 opaco y se confunden con facilidad.
  if (new URL(req.url).searchParams.get('ping') === '1') {
    const r = await conLimite(
      fetch(`https://api.cloudinary.com/v1_1/${CLOUD_NAME}/ping`, {
        headers: { Authorization: 'Basic ' + btoa(`${API_KEY}:${API_SECRET}`) },
      }), 8000, 'ping a Cloudinary')
    return json({
      credencialesValidas: r.ok,
      estadoCloudinary: r.status,
      apiKey: API_KEY,
      longitudSecret: API_SECRET.length,
      secretConEspacios: API_SECRET !== API_SECRET.trim(),
    })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: { headers: { Authorization: auth } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    )

    // auth_negocio_id() ya lee auth.uid() del propio JWT: si la sesión no vale,
    // devuelve null. Llamarla directamente evita un getUser() extra contra la
    // API de Auth — un viaje de red menos y un punto de cuelgue menos.
    const { data: negocioId, error } = await conLimite(
      supabase.rpc('auth_negocio_id'), 8000, 'auth_negocio_id',
    )

    if (error) {
      console.error('rpc auth_negocio_id:', error.message)
      return json({ error: 'No se pudo comprobar la sesión' }, 401)
    }
    if (!negocioId) return json({ error: 'Esta cuenta no tiene negocio' }, 403)

    // La carpeta la fija el servidor. Si viniera del cliente, un negocio podría
    // escribir en la carpeta de otro.
    const folder = `ventasroma/${negocioId}`
    const timestamp = Math.floor(Date.now() / 1000)

    // Cloudinary firma los parámetros ordenados alfabéticamente: folder, timestamp.
    const signature = await sha1(`folder=${folder}&timestamp=${timestamp}${API_SECRET}`)

    console.log('firma emitida para', folder)
    return json({
      cloudName: CLOUD_NAME,
      apiKey: API_KEY,
      timestamp,
      folder,
      signature,
      uploadUrl: `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`,
    })
  } catch (e) {
    console.error('firmar-subida:', String(e))
    return json({ error: String(e) }, 500)
  }
})
