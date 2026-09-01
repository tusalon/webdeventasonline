-- VentasRoma — orden del directorio por nivel de plan
--
-- Decisión de producto tomada por Raudael: las tiendas de nivel alto salen
-- primero. Queda dicho que esto convierte el directorio en un ranking de pago
-- y que el comprador lo nota; se asume a cambio de que los planes valgan más.
--
-- Dentro de un mismo nivel el orden ROTA CADA DÍA. Si fuera alfabético, la
-- tienda que empiece por A quedaría arriba para siempre y las demás nunca
-- aparecerían primero: una ventaja permanente que nadie compró.

create or replace view directorio
with (security_invoker = true) as
select
  n.id,
  n.slug,
  n.nombre,
  n.descripcion,
  n.logo_public_id,
  n.rubro,
  n.provincia,
  n.municipio,
  n.verificado,
  plan_vigente(n.id)                       as nivel,
  p.orden                                  as nivel_orden,
  -- Rotación diaria estable: igual durante todo el día, distinta mañana.
  md5(n.id::text || current_date::text)    as orden_dia,
  n.creado_en
from negocios n
join planes p on p.nivel = plan_vigente(n.id)
where n.activo;

comment on view directorio is
  'Tiendas activas con su nivel vigente. Ordenar por nivel_orden desc, orden_dia. security_invoker: aplica el RLS de negocios, no lo esquiva.';

grant select on directorio to anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- Repaso: el orden tal como lo verá el comprador
-- ─────────────────────────────────────────────────────────────
select nombre, nivel, verificado, provincia
from directorio
order by nivel_orden desc, orden_dia;
