// Avisos push al dueño del negocio.
//
// Dos motivos para existir:
//   - Pedido nuevo. El pedido ya le llega por WhatsApp, así que esto es
//     refuerzo, no el canal. Importa porque el mensaje de WhatsApp se pierde
//     entre otros veinte.
//   - Stock bajo. Esto SÍ es información nueva: nada más se la da, y es el
//     dolor que resuelve el producto — vender lo que ya no queda.
//
// La llama un trigger de la base, no el navegador: así el aviso va atado al
// dato que cambió y nadie puede saltárselo ni falsearlo.

import webpush from 'npm:web-push@3.6.7'
import { createClient } from 'jsr:@supabase/supabase-js@2'

// Se limpia todo lo que llega del entorno: pegar un secret en un panel web
// arrastra saltos de linea, espacios y comillas con una facilidad pasmosa, y
// web-push revienta con un error que no menciona el espacio por ningun lado.
const lee = (n: string) => Deno.env.get(n)?.trim().replace(/^["']|["']$/g, '') || ''

const SECRETO      = lee('SECRETO_NOTIFICAR')
const VAPID_PUBLIC = lee('VAPID_PUBLIC_KEY')
const VAPID_SECRET = lee('VAPID_PRIVATE_KEY')
const APP_URL      = lee('APP_URL')

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
 try {
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  if (!SECRETO || !VAPID_PUBLIC || !VAPID_SECRET) {
    console.error('faltan secrets de notificación')
    return json({ error: 'Sin configurar' }, 500)
  }
  // Solo la base puede disparar esto. Sin el secreto, cualquiera podría
  // bombardear a los dueños con avisos falsos.
  if (req.headers.get('x-secreto') !== SECRETO) return json({ error: 'No autorizado' }, 401)

  // Comprobar antes de llamar: web-push lanza y el trigger solo ve un 500 mudo.
  if (!/^[A-Za-z0-9_-]{80,90}$/.test(VAPID_PUBLIC)) {
    console.error(`VAPID_PUBLIC_KEY con formato invalido: ${VAPID_PUBLIC.length} caracteres`)
    return json({ error: 'La clave VAPID publica no es base64 URL-safe de 87 caracteres' }, 500)
  }

  try {
    webpush.setVapidDetails('mailto:hola@ventasroma.com', VAPID_PUBLIC, VAPID_SECRET)
  } catch (e) {
    console.error('setVapidDetails:', String(e))
    return json({ error: `Claves VAPID invalidas: ${String(e)}` }, 500)
  }

  // Se lee como TEXTO y se registra antes de interpretarlo. Un JSON invalido
  // aqui tumbaba la funcion con un 500 sin decir que habia llegado.
  const crudo = await req.text()
  console.log('cuerpo recibido:', crudo.slice(0, 500))

  let datos: Record<string, unknown>
  try {
    datos = JSON.parse(crudo)
  } catch {
    console.error('el cuerpo no es JSON. Primeros 200 caracteres:', crudo.slice(0, 200))
    return json({ error: 'El cuerpo no es JSON', recibido: crudo.slice(0, 200) }, 400)
  }

  const { tipo, negocio_id, titulo, cuerpo, url } = datos as {
    tipo?: string; negocio_id?: string; titulo?: string; cuerpo?: string; url?: string
  }
  if (!negocio_id || !titulo) {
    console.error('faltan datos en el cuerpo:', crudo.slice(0, 200))
    return json({ error: 'Faltan datos', recibido: datos }, 400)
  }

  // service_role: el trigger no tiene sesión de usuario, y esto lee las
  // suscripciones de un negocio concreto que la propia base acaba de indicar.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const { data: subs, error } = await supabase
    .from('push_subs').select('id, endpoint, p256dh, auth')
    .eq('negocio_id', negocio_id)

  if (error) {
    console.error('leyendo push_subs:', error.message)
    return json({ error: 'No se pudieron leer las suscripciones' }, 500)
  }
  if (!subs?.length) return json({ enviados: 0, motivo: 'sin dispositivos suscritos' })

  const carga = JSON.stringify({
    title: titulo,
    body: cuerpo ?? '',
    url: url ? `${APP_URL}${url}` : `${APP_URL}/admin`,
    tag: tipo ?? 'ventasroma',
  })

  // Se envía a todos los dispositivos del dueño en paralelo: puede tener el
  // móvil y el ordenador, y no sabemos cuál está mirando.
  const caducadas: string[] = []
  const envios = await Promise.allSettled(subs.map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        carga,
      )
    } catch (e) {
      // 404 y 410 = el navegador desinstaló la app o revocó el permiso.
      // Hay que borrarlas: si no, la tabla se llena de destinos muertos que
      // se reintentan en cada pedido para siempre.
      const codigo = (e as { statusCode?: number }).statusCode
      if (codigo === 404 || codigo === 410) caducadas.push(s.id)
      else console.error('push fallido:', codigo, String(e))
      throw e
    }
  }))

  if (caducadas.length) {
    await supabase.from('push_subs').delete().in('id', caducadas)
  }

  const ok = envios.filter((r) => r.status === 'fulfilled').length
  console.log(`avisos enviados: ${ok}/${subs.length}, caducadas borradas: ${caducadas.length}`)
  return json({ enviados: ok, total: subs.length, caducadas: caducadas.length })
 } catch (e) {
   // Cualquier fallo no previsto sale con su mensaje. pg_net solo guarda el
   // cuerpo de la respuesta: si aqui no se escribe nada util, el trigger
   // registra un "Internal Server Error" pelado y no hay por donde empezar.
   console.error('notificar reventó:', String(e), (e as Error)?.stack)
   return json({ error: String(e) }, 500)
 }
})