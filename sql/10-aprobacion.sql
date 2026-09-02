-- VentasRoma — una tienda nueva no se publica hasta que un admin la aprueba
--
-- Por qué una columna NUEVA y no reutilizar `activo`:
--
--   `activo` lo controla el DUEÑO — es su interruptor de "abierto/cerrado".
--   Las políticas ya le permiten actualizar su propio negocio, así que si la
--   aprobación viviera ahí, se aprobaría él solo y el control no existiría.
--
--   `aprobado` lo controla la PLATAFORMA. Un trigger impide que lo cambie
--   nadie que no sea admin, aunque llame a la API directamente con su sesión.
--
-- Visible al público = aprobado AND activo. Las dos cosas, de dos dueños
-- distintos.

alter table negocios add column if not exists aprobado boolean not null default false;

comment on column negocios.aprobado is
  'Lo pone la plataforma, no el dueño. Publicado = aprobado AND activo.';

-- Las tiendas que ya existían estaban publicadas: se dan por aprobadas.
-- Quitarles la visibilidad de golpe sería romperles la tienda sin avisar.
update negocios set aprobado = true where aprobado = false;

-- ─────────────────────────────────────────────────────────────
-- El dueño no puede aprobarse a sí mismo
-- ─────────────────────────────────────────────────────────────
create or replace function _proteger_aprobado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.aprobado is distinct from old.aprobado and not es_admin() then
    raise exception 'Solo un administrador de plataforma puede publicar una tienda';
  end if;
  return new;
end $$;

drop trigger if exists negocios_proteger_aprobado on negocios;
create trigger negocios_proteger_aprobado
  before update of aprobado on negocios
  for each row execute function _proteger_aprobado();

-- ─────────────────────────────────────────────────────────────
-- Lo público pasa a exigir las dos condiciones
-- ─────────────────────────────────────────────────────────────
drop policy if exists negocios_publico on negocios;
create policy negocios_publico on negocios
  for select using (activo and aprobado);

drop policy if exists categorias_publico on categorias;
create policy categorias_publico on categorias
  for select using (
    exists (select 1 from negocios n
            where n.id = categorias.negocio_id and n.activo and n.aprobado)
  );

drop policy if exists productos_publico on productos;
create policy productos_publico on productos
  for select using (
    activo and exists (select 1 from negocios n
                       where n.id = productos.negocio_id and n.activo and n.aprobado)
  );

drop policy if exists variantes_publico on variantes;
create policy variantes_publico on variantes
  for select using (
    activo and exists (
      select 1 from productos p join negocios n on n.id = p.negocio_id
      where p.id = variantes.producto_id and p.activo and n.activo and n.aprobado
    )
  );

-- El dueño sigue viendo lo suyo aunque no esté aprobado: tiene que poder
-- montar su catálogo mientras espera. Esa política ya existe y no cambia.

-- ─────────────────────────────────────────────────────────────
-- Y no se puede comprar en una tienda sin aprobar
-- ─────────────────────────────────────────────────────────────
-- Sin esto, alguien con el enlace directo podría pedir en una tienda que
-- todavía no ha pasado el control.
create or replace function _negocio_publicado(p_slug text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from negocios where slug = p_slug and activo and aprobado
$$;

-- ─────────────────────────────────────────────────────────────
-- El admin aprueba al activar el plan
-- ─────────────────────────────────────────────────────────────
create or replace function admin_activar_plan(
  p_negocio    uuid,
  p_nivel      text,
  p_hasta      timestamptz default null,
  p_verificado boolean     default null,
  p_notas      text        default null,
  p_aprobado   boolean     default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin() then
    raise exception 'Solo un administrador de plataforma puede cambiar planes'
      using errcode = '42501';
  end if;

  update negocios set
    plan            = coalesce(p_nivel, plan),
    plan_hasta      = p_hasta,
    plan_solicitado = null,
    verificado      = coalesce(p_verificado, verificado),
    plan_notas      = coalesce(p_notas, plan_notas),
    aprobado        = coalesce(p_aprobado, aprobado)
  where id = p_negocio;
end $$;

revoke all on function admin_activar_plan(uuid, text, timestamptz, boolean, text, boolean) from public;
grant execute on function admin_activar_plan(uuid, text, timestamptz, boolean, text, boolean)
  to authenticated;

-- ─────────────────────────────────────────────────────────────
-- El directorio solo muestra lo aprobado
-- ─────────────────────────────────────────────────────────────
create or replace view directorio
with (security_invoker = true) as
select
  n.id, n.slug, n.nombre, n.descripcion, n.logo_public_id,
  n.rubro, n.provincia, n.municipio, n.verificado,
  plan_vigente(n.id)                    as nivel,
  p.orden                               as nivel_orden,
  md5(n.id::text || current_date::text) as orden_dia,
  n.creado_en
from negocios n
join planes p on p.nivel = plan_vigente(n.id)
where n.activo and n.aprobado;

grant select on directorio to anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- Repaso
-- ─────────────────────────────────────────────────────────────
select nombre, slug, activo, aprobado, plan,
       case when activo and aprobado then 'publicada' else 'oculta' end as estado
from negocios order by aprobado, nombre;
