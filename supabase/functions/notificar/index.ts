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

const SECRETO      = Deno.env.get('SECRETO_NOTIFICAR')
const VAPID_PUBLIC = Deno.env.get('VAPID_PUBLIC_KEY')
const VAPID_SECRET = Deno.env.get('VAPID_PRIVATE_KEY')
const APP_URL      = Deno.env.get('APP_URL') ?? ''

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  if (!SECRETO || !VAPID_PUBLIC || !VAPID_SECRET) {
    console.error('faltan secrets de notificación')
    return json({ error: 'Sin configurar' }, 500)
  }
  // Solo la base puede disparar esto. Sin el secreto, cualquiera podría
  // bombardear a los dueños con avisos falsos.
  if (req.headers.get('x-secreto') !== SECRETO) return json({ error: 'No autorizado' }, 401)

  webpush.setVapidDetails(`mailto:hola@ventasroma.com`, VAPID_PUBLIC, VAPID_SECRET)

  const { tipo, negocio_id, titulo, cuerpo, url } = await req.json()
  if (!negocio_id || !titulo) return json({ error: 'Faltan datos' }, 400)

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
})
