# VentasRoma

Tienda online multi-tenant para negocios que venden por Instagram y WhatsApp:
ropa, comida, accesorios, lo que sea. Cada negocio tiene su catálogo público, su
panel para subir productos y llevar inventario, y recibe los pedidos ya
redactados por WhatsApp.

Parte del ecosistema Roma (RomaFinanzas, RomaCrece), pero sin atarse al sector
belleza: aquí el mercado es cualquiera que venda productos por redes.

## Cómo funciona

- **Una sola app para todos los negocios.** Cada uno es una fila en `negocios`
  con su `slug`; su tienda vive en `/t/{slug}`. Un repo, un despliegue, y una
  actualización sirve para todos.
- **Sin pasarela de pago.** El comprador arma el carrito y el pedido se cierra
  por WhatsApp con el detalle ya escrito. Funciona en Cuba, cero comisiones.
- **El stock vive en las variantes**, nunca en el producto. Un producto sin
  opciones tiene una variante llamada "Único". Una sola ruta de código para
  ropa con tallas, comida por libras y artesanía sin opciones.
- **Las imágenes van a Cloudinary** como `public_id`. La URL se construye al
  pintar con `f_auto,q_auto,w_600`, así que comprime y redimensiona solo — que
  es lo que hace que la tienda cargue con conexión lenta.

## Estructura

```
sql/01-esquema.sql      tablas, índices, crear_negocio(), crear_pedido()
sql/02-rls.sql          auth_negocio_id() y todas las políticas
sql/03-datos-demo.sql   datos de prueba + verificación de aislamiento
supabase/functions/     firmar-subida (Cloudinary), og-producto (vista previa)
LOVABLE.md              los prompts, por fases
```

El código de la app **no está aquí**: lo genera Lovable y lo sincroniza a este
mismo repo con su integración de GitHub.

## Puesta en marcha

1. Proyecto Supabase `pzjhvvslhawszjrtxhih` y cloud de Cloudinary `sqxv3vlt`. Propios,
   no compartidos con Rservasroma.
2. En el editor SQL de Supabase, ejecutar en orden `01`, `02` y `03`.
3. **`03` tiene que terminar en `OK — aislamiento, escritura, stock, variantes y
   buscador verificados`.** Si sale cualquier `FALLO:`, se arregla antes de seguir. El
   aislamiento entre negocios es la frontera de confianza de esta app: si el
   negocio A puede leer los pedidos de B, no hay producto.
4. `cp .env.example .env` y rellenar.
5. Secrets de las Edge Functions (no van al `.env` del front):
   ```bash
   supabase secrets set CLOUDINARY_API_KEY=... CLOUDINARY_API_SECRET=... APP_URL=...
   ```
6. Desplegar las funciones:
   ```bash
   supabase functions deploy firmar-subida og-producto
   ```
7. Abrir `LOVABLE.md` y pegar los prompts, uno por fase.

## Comprobaciones que importan

**Aislamiento** — se vuelve a lanzar `03-datos-demo.sql` cada vez que cambie el
esquema. Es el único de estos que bloquea el lanzamiento.

**Vista previa del link** — pegar la URL de un producto en un chat real de
WhatsApp: tiene que salir con foto, nombre y precio. Lo que decide es lo que ve
el robot:
```bash
curl -s https://pzjhvvslhawszjrtxhih.supabase.co/functions/v1/og-producto/demo-ropa/vestido-rojo | grep -i 'og:'
```

**Subida de imágenes** — pedir firma sin sesión tiene que devolver 401:
```bash
curl -s -X POST https://pzjhvvslhawszjrtxhih.supabase.co/functions/v1/firmar-subida -o /dev/null -w '%{http_code}\n'
```

## Notas de despliegue

- **`og-producto` necesita estar delante de las URLs que se comparten.** Si se
  comparte directamente la ruta de la SPA, el robot de WhatsApp no ejecuta
  JavaScript y el link se pega pelado. Al fijar el dominio hay que decidir cómo
  se enruta: por ahora el botón de compartir copia la URL de la función.
- **El keystore del APK se genera una vez y no se pierde nunca.** Va a GitHub
  Secrets y a un backup fuera de GitHub. Perderlo significa no poder volver a
  actualizar la app instalada, jamás.
- **En iOS no hay APK.** La PWA instalada es la única vía, y el push solo
  funciona desde iOS 16.4 y con la app añadida a inicio.

El plan completo, con el análisis de la competencia y los riesgos, está en
`~/.claude/plans/c-users-rodo-documents-pagina-de-ventas-fizzy-taco.md`.

## Cloudinary: la API key necesita un rol

Al crear una API key nueva, Cloudinary la deja **sin ningún rol asignado**. La
key parece válida —el ping de credenciales responde 200, porque leer sí puede—
pero cualquier subida falla con:

```
403 Request forbidden due to missing permissions (actions=["create"])
```

En Settings → API Keys → la key → **Assign product environment-level roles**,
hay que darle un rol que permita crear recursos (Master Admin, o Media Library
User con permiso de escritura sobre `ventasroma/`).

Diagnóstico rápido, sin exponer el secret:

```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/firmar-subida?ping=1" -H "Authorization: Bearer $JWT"
```

Devuelve si el par key/secret es válido, la longitud del secret y si trae
espacios al pegar. Separa "credenciales mal" de "firma mal construida", que
dan errores parecidos y se confunden con facilidad.

**Y la key y el secret van siempre en pareja.** Al rotar, Cloudinary genera un
par nuevo entero: cambiar solo el secret y dejar la key vieja da un 401 de firma
inválida que no dice nada sobre la causa real.

## Estado a 30 de agosto de 2026

Verificado en producción sobre `ventasroma26.com`, con Supabase
`pzjhvvslhawszjrtxhih` y Cloudinary `sqxv3vlt`.

**Fase 1 — Tienda pública.** Catálogo, categorías, ficha con variantes, buscador
sin acentos, carrito y checkout por WhatsApp. Probado con pedidos reales que
descuentan stock en transacción.

**Fase 2 — Panel.** Alta de negocio, productos con tallas, inventario, pedidos,
ajustes, imágenes firmadas a Cloudinary. **Aislamiento verificado con un usuario
nacido del registro real**: no ve los pedidos de otro negocio.

**Fase 3 — PWA y avisos.** Instalable, service worker, push de pedido nuevo y de
stock bajo, ambos recibidos en un móvil real con la app cerrada.

### Pendiente

- Dominio propio. Solo bloquea el APK (fase 4); todo lo demás corre en lovable.app.
- Los dos negocios piloto con catálogo real.
- `start_url` es `/admin`: un comprador que instale la tienda aterriza en el login.

### Lo que cuesta horas si no se sabe

- **Una API key nueva de Cloudinary nace sin roles.** El ping responde 200 porque
  leer sí puede, pero subir da 403. Y al rotar hay que cambiar key y secret juntos.
- **En PL/pgSQL, los argumentos con nombre van con `=>`, nunca con `:=`.** Con `:=`
  se interpretan por posición sin avisar.
- **pg_net 0.20.4 mete las cabeceras HTTP dentro del cuerpo.** Hay que buscar dónde
  empieza el JSON.
- **Las Edge Functions exigen JWT por defecto.** Las que llama un robot o un trigger
  necesitan `verify_jwt = false` en `config.toml`.
- **El ahorro de batería de Android retiene los push.** Llegan todos de golpe al
  enchufar. Por eso el pedido nunca puede depender solo del aviso: WhatsApp es el
  canal, el push es refuerzo.
