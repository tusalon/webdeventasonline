# Prompts para Lovable

Se pegan **de uno en uno**, en orden, esperando a que cada fase funcione antes de
seguir. Pegar todo junto produce una app que compila y no sirve.

**Antes de empezar:** el SQL de `sql/` ya tiene que estar ejecutado en Supabase, y
la verificación de `03-datos-demo.sql` tiene que haber terminado en
`OK — aislamiento, stock, variantes y buscador verificados`.

---

## Regla permanente (pegar al principio del proyecto)

```
Contexto fijo de este proyecto. Respétalo en todo lo que generes:

- El esquema de la base de datos YA EXISTE en Supabase y NO se toca. No generes
  migraciones, no crees tablas, no modifiques políticas RLS. Si crees que falta
  una columna, dilo en texto y espera; no la crees.
- Las tablas son: negocios, perfiles, categorias, productos, variantes, pedidos,
  pedido_items, push_subs.
- El stock vive SIEMPRE en `variantes`, nunca en `productos`. Todo producto tiene
  al menos una variante; si no tiene opciones, se llama "Único" y en la interfaz
  no se muestra el selector.
- Los pedidos se crean SOLO llamando a la función `crear_pedido` por RPC. Nunca
  insertes en `pedidos` ni en `pedido_items` desde el cliente, y nunca descuentes
  stock con un UPDATE: hay condiciones de carrera y la función ya las resuelve.
- El alta de negocio se hace SOLO con la RPC `crear_negocio`.
- Las imágenes se guardan como `public_id` de Cloudinary, nunca como URL. La URL
  se construye al pintar:
  https://res.cloudinary.com/{cloud}/image/upload/f_auto,q_auto,w_600/{public_id}
  Usa w_600 en listados y w_1200 en la ficha. No redimensiones en el navegador.
- Móvil primero. La mayoría de la gente entra desde el link de la bio de
  Instagram, en un móvil, con conexión lenta. Nada de tablas anchas ni menús
  que necesiten ratón.
- Todo en español. Moneda formateada con separador de miles.
- Sin pasarela de pago. Nunca. El pedido se cierra por WhatsApp.
```

---

## Fase 1 — Tienda pública

```
Construye la parte pública de VentasRoma, una tienda online multi-tenant.
Sin login: todo esto lo ve un comprador cualquiera.

Rutas:
  /t/:negocio               catálogo
  /t/:negocio/c/:categoria  productos de una categoría
  /t/:negocio/p/:producto   ficha del producto
  /t/:negocio/buscar        buscador
  /t/:negocio/info          datos del negocio
  /t/:negocio/carrito       carrito y checkout

Catálogo: cabecera con portada, logo, nombre del negocio e icono de verificado
si `negocios.verificado`. Tira de categorías desplazable en horizontal. Rejilla
de dos columnas en móvil con foto, nombre, precio y badges:
  - "Popular" si `destacado`
  - "Ahorra X%" si hay `precio_anterior` (calcula el porcentaje y tacha el precio viejo)
  - "Agotado" si la suma del stock de sus variantes activas es 0
Un producto agotado se muestra en gris y no se puede añadir.

Si el negocio tiene `moneda_alt` y `tasa_alt`, muestra debajo del precio el
equivalente en la otra moneda, más pequeño y en gris.

Ficha del producto: carrusel de imágenes, nombre, precio, descripción. Si el
producto tiene más de una variante activa, muestra un selector de píldoras con
sus nombres; las de stock 0 salen deshabilitadas. Si solo tiene la variante
"Único", no muestres selector alguno. Selector de cantidad limitado al stock de
la variante elegida. Botón "Añadir al carrito" y botón de compartir que copie
la URL de la ficha.

Buscador: campo que consulta `productos` filtrando por `busqueda` con
textSearch de Supabase, configuración 'spanish'. Debe encontrar sin importar
acentos ni mayúsculas. Resultados con la misma tarjeta del catálogo.

/info: descripción, dirección, municipio, provincia, horario, teléfono, botón de
WhatsApp, y si hay domicilio o recogida.

Carrito: en localStorage, con clave por negocio para que dos tiendas no se
mezclen. Muestra líneas con foto, nombre, variante, cantidad editable y subtotal.

Checkout: nombre, teléfono, elegir domicilio o recogida entre los que el negocio
tenga activos, y nota opcional. Al confirmar llama a la RPC `crear_pedido` con
{ p_negocio_slug, p_cliente_nombre, p_cliente_telefono, p_items, p_entrega, p_nota }
donde p_items es [{ variante_id, cantidad }].
Si devuelve error, muéstralo tal cual: el mensaje ya dice qué producto se quedó
sin stock. No reintentes automáticamente.
Si va bien, vacía el carrito y abre
https://wa.me/{whatsapp sin +}?text={mensaje}
con el mensaje ya redactado, encodeURIComponent y saltos de línea reales:

  Pedido nuevo
  2 x Vestido rojo — M ... 8000 CUP
  1 x Cake de vainilla ... 2500 CUP
  Total: 10500 CUP
  Cliente: Ana / +5355559999
  Entrega: domicilio

Muestra también una pantalla de confirmación con un botón para reabrir WhatsApp,
porque el bloqueador de pop-ups a veces se come el primer intento.
```

---

## Fase 2 — Panel del dueño

```
Añade el panel privado en /admin, detrás de Supabase Auth con email y contraseña.

Alta: si el usuario entra y no tiene negocio, un asistente de un solo paso pide
nombre del negocio, dirección de la tienda (el slug, con vista previa de la URL
final y aviso si ya está cogido), WhatsApp con código de país y rubro. Si la URL
traía ?ref=CODIGO, pásalo. Llama a la RPC `crear_negocio`.
Según el rubro, precarga categorías sugeridas y déjalas editables:
  ropa → Vestidos, Blusas, Pantalones, Calzado, Accesorios
  alimentos → Dulces, Salados, Bebidas, Encargos
  belleza → Uñas, Maquillaje, Cabello, Cuidado de la piel
  otro → sin precargar

Productos: lista con buscador y filtro por categoría. El alta pide nombre,
descripción, precio, categoría e imágenes. Sin límite de fotos.
Subida de imágenes: primero POST a la Edge Function `firmar-subida`, y con lo
que devuelve sube directo a Cloudinary con FormData
(file, api_key, timestamp, folder, signature). Guarda el `public_id` que
devuelve Cloudinary en el array `imagenes`. Nunca guardes la URL completa.
El primer campo de stock que ve el dueño es un número suelto: por debajo edita
la variante "Único". Solo si pulsa "Añadir tallas u opciones" aparece la tabla de
variantes con nombre, diferencia de precio, stock y stock mínimo. Un producto
que no necesita opciones nunca debe ver esa tabla.

Pedidos: lista ordenada por fecha descendente, con estado en pestañas
(nuevo / preparando / entregado / cancelado) y contador de nuevos. Al abrir uno,
sus líneas, el total, los datos del cliente y botones para escribirle por
WhatsApp y para cambiar el estado.

Inventario: vista con todas las variantes ordenadas por stock ascendente, en
rojo las que están por debajo de su stock mínimo. Edición del stock en línea.

Ajustes del negocio: todos los campos de `negocios` menos plan, verificado,
codigo_referido y referido_por, que no se tocan desde aquí. Incluye horario por
día, modos de entrega, y moneda alternativa con su tasa.
```

---

## Fase 3 — PWA y notificaciones

```
Convierte la app en PWA instalable y añade notificaciones push al dueño.

manifest.json con nombre, iconos de 192 y 512, display standalone, color de
tema y start_url en /admin. Service worker con Workbox: cachea el armazón de la
app, y las imágenes de Cloudinary con stale-while-revalidate. La app tiene que
pasar la auditoría PWA de Lighthouse — sin eso no se puede generar el APK.

En el panel, una tarjeta "Recibir avisos en este dispositivo" que pida permiso,
se suscriba con la clave VAPID pública y guarde la suscripción en `push_subs`.
Si el usuario está en iPhone y no ha instalado la app, explícale que en iOS los
avisos solo llegan con la app instalada desde el botón Compartir → Añadir a
inicio, y enséñale cómo. No le pidas el permiso ahí: en iOS falla en silencio.

Deja claro en la interfaz que el aviso es un refuerzo, no el canal: el pedido
llega igual por WhatsApp.
```

---

## Fase 6 — Directorio y referidos

```
Añade en / un directorio de tiendas: lista `negocios` activos con logo, nombre,
rubro, provincia e icono de verificado. Filtros por rubro y provincia, y
buscador por nombre. Cada tarjeta lleva a /t/:slug.

En el pie de cada tienda pública, "Crea tu tienda en VentasRoma" apuntando a
/registro?ref={codigo_referido de ese negocio}.

En el panel, una sección con el link de referido del negocio, botón de copiar, y
cuántos negocios se han dado de alta con él.
```

---

## Cosas que Lovable suele hacer mal aquí

Si aparece cualquiera de estas, se corrige antes de seguir:

- **Regenera el esquema o las políticas RLS.** Es el fallo más caro: rompe el
  aislamiento entre negocios en silencio. El SQL de `sql/` es la fuente de
  verdad; si el esquema cambia, se vuelve a ejecutar `03-datos-demo.sql`.
- **Descuenta stock con un UPDATE** en vez de dejárselo a `crear_pedido`.
- **Guarda la URL de Cloudinary** en vez del `public_id`, y adiós a las
  transformaciones y al ahorro de datos.
- **Sube con un preset sin firmar** porque es más rápido que llamar a la
  Edge Function. Deja la cuenta abierta a cualquiera.
- **Trata el stock como campo del producto**, y las variantes dejan de cuadrar.
- **Mete una pasarela de pago** porque "una tienda la lleva". No.
