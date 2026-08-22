-- VentasRoma — carga de un negocio piloto real
--
-- Esto NO es parte de la instalación (01, 02, 03). Es la plantilla para meter
-- los dos negocios piloto con su catálogo de verdad, antes de que exista el
-- panel de administración.
--
-- Por qué antes: construir la app contra productos reales destapa lo que un
-- "vestido-rojo" de mentira no enseña nunca — nombres larguísimos que rompen la
-- tarjeta, precios de 5 cifras, fotos verticales, categorías que se solapan,
-- productos sin descripción. Si Lovable se construye contra datos falsos, esos
-- problemas aparecen el día del lanzamiento.
--
-- Cómo usarla:
--   1. Subir las fotos a Cloudinary a mano, a la carpeta ventasroma/{negocio_id}
--      (el negocio_id lo eliges tú abajo, no hace falta que exista antes).
--   2. Copiar el `public_id` que da Cloudinary — NO la URL.
--   3. Rellenar los bloques de abajo y ejecutar.
--   4. Abrir /t/{slug} cuando la Fase 1 esté en pie y mirarlo en un móvil real.

begin;

-- ═════════════════════════════════════════════════════════════
-- NEGOCIO PILOTO 1 — ropa (el que necesita tallas)
-- ═════════════════════════════════════════════════════════════
-- Genera un uuid nuevo con: select gen_random_uuid();
\set negocio1 '00000000-0000-0000-0000-000000000000'

insert into negocios (
  id, slug, nombre, descripcion,
  whatsapp,            -- E.164 obligatorio: +53........ Sin esto los pedidos se pierden
  telefono, direccion, municipio, provincia,
  rubro, moneda, moneda_alt, tasa_alt,
  entrega_domicilio, entrega_recogida,
  horario
) values (
  :'negocio1',
  'nombre-de-la-tienda',          -- será ventasroma.com/t/ESTO — minúsculas y guiones
  'Nombre de la Tienda',
  'Una o dos frases. Sale en /info y en la vista previa del link.',
  '+5350000000',
  null, 'Calle y número', 'Municipio', 'La Habana',
  'ropa', 'CUP', 'USD', 420,      -- tasa_alt: la que use el negocio ese día
  true, true,
  '{"lun":"9:00-18:00","mar":"9:00-18:00","mie":"9:00-18:00",
    "jue":"9:00-18:00","vie":"9:00-18:00","sab":"9:00-13:00","dom":null}'::jsonb
);

insert into categorias (negocio_id, slug, nombre, orden) values
  (:'negocio1', 'vestidos',  'Vestidos',  1),
  (:'negocio1', 'blusas',    'Blusas',    2),
  (:'negocio1', 'pantalones','Pantalones',3);

-- ── Un producto CON tallas ────────────────────────────────────
with p as (
  insert into productos (negocio_id, categoria_id, slug, nombre, descripcion,
                         precio_base, precio_anterior, destacado, imagenes)
  values (
    :'negocio1',
    (select id from categorias where negocio_id = :'negocio1' and slug = 'vestidos'),
    'vestido-flores',
    'Vestido de flores',
    'Algodón, manga corta',
    4500,
    null,                      -- poner el precio viejo SOLO si hay rebaja real
    true,                      -- destacado = badge "Popular"
    array['ventasroma/xxx/vestido-flores-1','ventasroma/xxx/vestido-flores-2']
  ) returning id
)
-- El trigger ya creó la variante "Único"; en ropa se sustituye por tallas.
, v as (
  insert into variantes (producto_id, nombre, precio_delta, stock, stock_minimo, orden)
  select p.id, t.nombre, 0, t.stock, 1, t.orden
  from p, (values ('S',4,1),('M',6,2),('L',3,3),('XL',0,4)) as t(nombre,stock,orden)
  returning producto_id
)
delete from variantes
 where producto_id = (select distinct producto_id from v) and nombre = 'Único';

-- ── Un producto SIN opciones ──────────────────────────────────
with p as (
  insert into productos (negocio_id, categoria_id, slug, nombre, descripcion,
                         precio_base, imagenes)
  values (
    :'negocio1',
    (select id from categorias where negocio_id = :'negocio1' and slug = 'blusas'),
    'bolso-tejido', 'Bolso tejido', null, 2800,
    array['ventasroma/xxx/bolso-tejido-1']
  ) returning id
)
update variantes set stock = 7, stock_minimo = 2
 where producto_id = (select id from p);      -- edita la variante "Único", no crea otra

-- ═════════════════════════════════════════════════════════════
-- NEGOCIO PILOTO 2 — alimentos (sin variantes, o por unidad de venta)
-- ═════════════════════════════════════════════════════════════
\set negocio2 '00000000-0000-0000-0000-000000000000'

insert into negocios (id, slug, nombre, descripcion, whatsapp,
                      municipio, provincia, rubro, moneda,
                      entrega_domicilio, entrega_recogida, horario)
values (
  :'negocio2', 'dulceria-ejemplo', 'Dulcería Ejemplo',
  'Encargos con 24 horas de antelación.',
  '+5350000001', 'Vedado', 'La Habana', 'alimentos', 'CUP',
  true, true,
  '{"lun":"8:00-17:00","sab":"8:00-14:00","dom":null}'::jsonb
);

insert into categorias (negocio_id, slug, nombre, orden) values
  (:'negocio2', 'dulces',  'Dulces',  1),
  (:'negocio2', 'bebidas', 'Bebidas', 2);

-- En comida las "tallas" suelen ser tamaños o presentaciones, y ahí el
-- precio_delta sí se usa: el mismo producto vale distinto según el tamaño.
with p as (
  insert into productos (negocio_id, categoria_id, slug, nombre, descripcion,
                         precio_base, imagenes)
  values (
    :'negocio2',
    (select id from categorias where negocio_id = :'negocio2' and slug = 'dulces'),
    'cake-chocolate', 'Cake de chocolate', 'Por encargo, 24 horas',
    2500,                       -- precio del tamaño más pequeño
    array['ventasroma/yyy/cake-chocolate-1']
  ) returning id
)
, v as (
  insert into variantes (producto_id, nombre, precio_delta, stock, stock_minimo, orden)
  select p.id, t.nombre, t.delta, t.stock, 0, t.orden
  from p, (values ('6 porciones',0,5,1),('12 porciones',1800,3,2),('20 porciones',3600,2,3))
           as t(nombre,delta,stock,orden)
  returning producto_id
)
delete from variantes
 where producto_id = (select distinct producto_id from v) and nombre = 'Único';

commit;

-- ═════════════════════════════════════════════════════════════
-- Repaso: lo que rompe una tienda el día del lanzamiento
-- ═════════════════════════════════════════════════════════════
select n.nombre as negocio,
       count(distinct p.id)                        as productos,
       count(v.id)                                 as variantes,
       count(*) filter (where v.stock = 0)         as agotadas,
       count(distinct p.id) filter (where cardinality(p.imagenes) = 0) as sin_foto,
       count(distinct p.id) filter (where p.descripcion is null)       as sin_descripcion,
       max(length(p.nombre))                       as nombre_mas_largo
from negocios n
join productos p on p.negocio_id = n.id
join variantes v on v.producto_id = p.id
where n.slug in ('nombre-de-la-tienda', 'dulceria-ejemplo')
group by n.nombre;

-- sin_foto > 0        → la tarjeta sale vacía y el link se pega sin imagen
-- nombre_mas_largo    → por encima de ~40 se desborda la tarjeta en móvil
-- agotadas = todas    → el producto sale en gris y no se puede pedir
