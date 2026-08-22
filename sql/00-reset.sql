-- VentasRoma — reset
--
-- Borra todo lo que crean 01, 02 y 03 para poder volver a empezar limpio.
-- Hace falta cuando 01 se queda a medias (por ejemplo si se pegó cortado) y
-- al reintentar sale "type rubro_t already exists".
--
-- ⚠️ Esto BORRA todos los negocios, productos y pedidos. En un proyecto con
-- clientes reales dentro NO se ejecuta: se escribe una migración.
--
-- Después: 01 → 02 → 03, cada uno completo.

drop table if exists
  push_subs, pedido_items, pedidos, variantes, productos, categorias, perfiles, negocios
  cascade;

-- CASCADE se lleva por delante crear_pedido() y crear_negocio(), que usan estos tipos.
drop type if exists entrega_t, estado_pedido_t, rol_t, rubro_t cascade;

drop function if exists auth_negocio_id();
drop function if exists _variante_por_defecto();
drop function if exists _proteger_ultima_variante();
drop function if exists public.unaccent_inm(text);

delete from auth.users where email like '%@ventasroma.test';
