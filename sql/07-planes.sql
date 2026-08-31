-- VentasRoma — planes, límites y administración de plataforma
--
-- Ejecutar después de 01..06.
--
-- Hoy cualquiera se registra y usa todo sin límite, así que no hay nada que
-- vender. Esto convierte `negocios.plan` —que existía sin usar desde el
-- principio— en algo con consecuencias.

-- ═════════════════════════════════════════════════════════════
-- 1. Los planes
-- ═════════════════════════════════════════════════════════════
-- En tabla y no en el código: estos límites se van a ajustar en cuanto se vea
-- cómo se usan de verdad, y cambiar una fila es más barato que republicar.
create table if not exists planes (
  nivel              text primary key,
  nombre             text not null,
  max_productos      int,            -- null = sin límite
  max_fotos_producto int  not null,
  orden              int  not null
);

insert into planes (nivel, nombre, max_productos, max_fotos_producto, orden) values
  ('base',    'Base',      15,  3, 1),
  ('silver',  'Silver',    50,  5, 2),
  ('gold',    'Gold',     200,  8, 3),
  ('diamond', 'Diamond',  null, 12, 4)
on conflict (nivel) do update set
  nombre = excluded.nombre,
  max_productos = excluded.max_productos,
  max_fotos_producto = excluded.max_fotos_producto,
  orden = excluded.orden;

alter table planes enable row level security;
drop policy if exists planes_lectura on planes;
create policy planes_lectura on planes for select using (true);
revoke insert, update, delete on planes from anon, authenticated;

-- ═════════════════════════════════════════════════════════════
-- 2. Campos de plan en negocios
-- ═════════════════════════════════════════════════════════════
alter table negocios
  add column if not exists plan_hasta      timestamptz,
  add column if not exists plan_solicitado text,
  add column if not exists plan_notas      text;

-- El campo `plan` existía sin restricción. Ahora tiene que ser un nivel real.
update negocios set plan = 'base'
 where plan is null or plan not in (select nivel from planes);

alter table negocios drop constraint if exists negocios_plan_valido;
alter table negocios add constraint negocios_plan_valido
  foreign key (plan) references planes(nivel);

alter table negocios drop constraint if exists negocios_plan_solicitado_valido;
alter table negocios add constraint negocios_plan_solicitado_valido
  foreign key (plan_solicitado) references planes(nivel);

comment on column negocios.plan_hasta is
  'Cuándo vence el plan. Null = sin vencimiento. Vencido se comporta como base.';
comment on column negocios.plan_solicitado is
  'Plan que pidió el negocio al registrarse, pendiente de que se confirme el pago.';

-- ═════════════════════════════════════════════════════════════
-- 3. Nivel vigente — se calcula al leer, sin tarea programada
-- ═════════════════════════════════════════════════════════════
-- Un cron que baje planes vencidos puede fallar en silencio y dejar a alguien
-- pagando de más o disfrutando de más. Calculado al leer, eso no puede pasar.
create or replace function plan_vigente(p_negocio uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
           when n.plan_hasta is not null and n.plan_hasta < now() then 'base'
           else n.plan
         end
  from negocios n
  where n.id = p_negocio
$$;

-- ═════════════════════════════════════════════════════════════
-- 4. Los límites viven en la base, no en la interfaz
-- ═════════════════════════════════════════════════════════════
-- Si el tope solo estuviera en el panel, cualquiera con la clave anon lo
-- saltaría llamando a la API. La regla va donde no se puede esquivar.
create or replace function _limite_productos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nivel  text;
  v_max    int;
  v_actual int;
begin
  v_nivel := plan_vigente(new.negocio_id);
  select max_productos into v_max from planes where nivel = v_nivel;

  if v_max is null then return new; end if;   -- diamond

  select count(*) into v_actual from productos where negocio_id = new.negocio_id;

  if v_actual >= v_max then
    raise exception
      'El plan % permite % productos y ya tienes %. Mejora el plan para añadir más.',
      v_nivel, v_max, v_actual
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists productos_limite_plan on productos;
create trigger productos_limite_plan
  before insert on productos for each row execute function _limite_productos();

create or replace function _limite_fotos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_max int;
begin
  select p.max_fotos_producto into v_max
  from planes p where p.nivel = plan_vigente(new.negocio_id);

  if cardinality(new.imagenes) > v_max then
    raise exception 'El plan % permite % fotos por producto.',
      plan_vigente(new.negocio_id), v_max
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists productos_limite_fotos on productos;
create trigger productos_limite_fotos
  before insert or update of imagenes on productos
  for each row execute function _limite_fotos();

-- ═════════════════════════════════════════════════════════════
-- 5. Administrador de plataforma
-- ═════════════════════════════════════════════════════════════
-- ⚠️ Esta es la parte delicada: abre una excepción en el aislamiento entre
-- negocios. Se limita a `negocios` y NUNCA se extiende a `pedidos`, donde
-- están los teléfonos de los clientes. Para activar un plan no hace falta
-- verlos.
create table if not exists admins_plataforma (
  id        uuid primary key references auth.users(id) on delete cascade,
  creado_en timestamptz not null default now()
);
alter table admins_plataforma enable row level security;
-- Sin políticas a propósito: no se lee desde la API con ninguna clave.
revoke all on admins_plataforma from anon, authenticated;

create or replace function es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins_plataforma where id = auth.uid())
$$;
revoke all on function es_admin() from public;
grant execute on function es_admin() to authenticated;

-- El admin puede LEER todos los negocios.
drop policy if exists negocios_admin_ver on negocios;
create policy negocios_admin_ver on negocios
  for select to authenticated using (es_admin());

-- Y NO tiene política de UPDATE a propósito.
--
-- RLS no sabe restringir por columna: una política de update le daría poder
-- para cambiar el WhatsApp, el slug o el nombre de cualquier tienda. En su
-- lugar, una función que solo toca los cuatro campos del plan. Es el mismo
-- patrón que ya protege `pedidos` con `crear_pedido`.
create or replace function admin_activar_plan(
  p_negocio    uuid,
  p_nivel      text,
  p_hasta      timestamptz default null,
  p_verificado boolean     default null,
  p_notas      text        default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin() then
    raise exception 'Solo un administrador de plataforma puede cambiar planes'
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from planes where nivel = p_nivel) then
    raise exception 'Plan inexistente: %', p_nivel;
  end if;

  update negocios set
    plan            = p_nivel,
    plan_hasta      = p_hasta,
    plan_solicitado = null,          -- la solicitud queda atendida
    verificado      = coalesce(p_verificado, verificado),
    plan_notas      = coalesce(p_notas, plan_notas)
  where id = p_negocio;
end $$;
revoke all on function admin_activar_plan(uuid, text, timestamptz, boolean, text) from public;
grant execute on function admin_activar_plan(uuid, text, timestamptz, boolean, text) to authenticated;

-- ═════════════════════════════════════════════════════════════
-- 6. Darte de alta como administrador
-- ═════════════════════════════════════════════════════════════
-- Sustituye el correo por el tuyo y ejecuta esta línea aparte:
--
--   insert into admins_plataforma (id)
--   select id from auth.users where email = 'TU_CORREO'
--   on conflict (id) do nothing;

-- ═════════════════════════════════════════════════════════════
-- Repaso
-- ═════════════════════════════════════════════════════════════
select n.nombre, n.plan, plan_vigente(n.id) as vigente, n.plan_hasta,
       n.plan_solicitado, n.verificado,
       (select count(*) from productos p where p.negocio_id = n.id) as productos,
       (select max_productos from planes where nivel = plan_vigente(n.id)) as tope
from negocios n
order by n.nombre;
