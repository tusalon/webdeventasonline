// Vista previa del producto para WhatsApp e Instagram.
//
// Por qué existe: Lovable genera una SPA de Vite. Las etiquetas og: no existen
// hasta que corre JavaScript, y el robot de WhatsApp no ejecuta JavaScript. Sin
// esto, el link del producto se pega gris y pelado — justo el caso de uso
// principal del producto entero.
//
// Sin detección de user-agent a propósito: se sirven las etiquetas a todo el
// mundo y se rebota al humano con un redirect. Adivinar quién es un bot por la
// cabecera se rompe cada vez que alguien cambia su user-agent.
//
// Uso:  /functions/v1/og-producto/{negocio}/{producto}

import { createClient } from 'jsr:@supabase/supabase-js@2'

// Sin esquema, Response.redirect() lanza y la funcion muere con un 500.
// Normalizar aqui cuesta una linea y evita depender de como se escribio el secret.
const crudo = Deno.env.get('APP_URL')?.trim().replace(/\/+$/, '') || 'https://ventasroma.com'
const APP_URL = /^https?:\/\//.test(crudo) ? crudo : `https://${crudo}`
const CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME')!

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

Deno.serve(async (req) => {
  const partes = new URL(req.url).pathname.split('/').filter(Boolean)
  const [negocioSlug, productoSlug] = partes.slice(-2)
  const destino = `${APP_URL}/t/${negocioSlug}/p/${productoSlug}`

  // Cliente anónimo: lee solo lo que RLS deja ver en público. Correcto —
  // un producto desactivado no debe tener vista previa.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
  )

  const { data: negocio } = await supabase
    .from('negocios').select('id, nombre, moneda')
    .eq('slug', negocioSlug).maybeSingle()

  const { data: producto } = negocio
    ? await supabase
        .from('productos').select('nombre, descripcion, precio_base, imagenes')
        .eq('negocio_id', negocio.id).eq('slug', productoSlug).maybeSingle()
    : { data: null }

  // Sin producto no se inventa una vista previa: se manda a la tienda. Con HTML
  // y no con Response.redirect() porque los robots no siempre siguen redirecciones
  // — y porque un producto borrado no puede tumbar la funcion con un 500.
  if (!producto) {
    const tienda = `${APP_URL}/t/${negocioSlug}`
    const nombre = negocio?.nombre ?? 'VentasRoma'
    return new Response(
      `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>${esc(nombre)}</title>
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(nombre)}">
<meta property="og:description" content="Este producto ya no esta disponible.">
<meta property="og:url" content="${esc(tienda)}">
<meta http-equiv="refresh" content="0;url=${esc(tienda)}">
</head><body><a href="${esc(tienda)}">${esc(nombre)}</a></body></html>`,
      { status: 404, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
    )
  }

  const titulo = `${producto.nombre} — ${negocio!.nombre}`
  const precio = `${producto.precio_base} ${negocio!.moneda}`
  const desc = producto.descripcion?.trim() || precio
  const imagen = producto.imagenes?.[0]
    ? `https://res.cloudinary.com/${CLOUD_NAME}/image/upload/f_auto,q_auto,w_1200,c_fill,ar_1.91/${producto.imagenes[0]}`
    : `${APP_URL}/og-default.png`

  return new Response(
    `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>${esc(titulo)}</title>
<meta property="og:type" content="product">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(destino)}">
<meta property="product:price:amount" content="${producto.precio_base}">
<meta property="product:price:currency" content="${esc(negocio!.moneda)}">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="${esc(destino)}">
<meta http-equiv="refresh" content="0;url=${esc(destino)}">
</head><body><a href="${esc(destino)}">${esc(titulo)} — ${esc(precio)}</a></body></html>`,
    {
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        // Los robots reintentan; que no golpeen la base cada vez.
        'Cache-Control': 'public, max-age=300',
      },
    },
  )
})
