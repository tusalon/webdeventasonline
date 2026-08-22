-- VentasRoma — esquema
-- Ejecutar en el editor SQL de Supabase ANTES de conectar Lovable.
-- Orden: 01-esquema.sql → 02-rls.sql → 03-datos-demo.sql

create extension if not exists unaccent with schema extensions;

-- unaccent() no es IMMUTABLE, así que no se puede usar en una columna generada.
-- Este envoltorio con el diccionario fijado sí lo es.
create or replace function public.unaccent_inm(text)
returns text language sql immutable strict parallel safe as $$
  select extensions.unaccent('extensions.unaccent', $1)
$$;

create type rubro_t         as enum ('ropa','alimentos','accesorios','belleza','hogar','otro');
create type rol_t           as enum ('dueno','vendedor');
create type estado_pedido_t as enum ('nuevo','preparando','entregado','cancelado');
create type entrega_t       as enum ('domicilio','recogida');

-- ─────────────────────────────────────────────────────────────
-- Negocios (tenants)
-- ─────────────────────────────────────────────────────────────
create table negocios (
  id                uuid primary key default gen_random_uuid(),
  slug              text not null unique
                      check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 40),
  nombre            text not null check (length(trim(nombre)) > 0),
  descripcion       text,
  -- E.164. Sin esto los pedidos se van al vacío.
  whatsapp          text not null check (whatsapp ~ '^\+[1-9][0-9]{7,14}$'),
  telefono          text,
  logo_public_id    text,
  portada_public_id text,
  direccion         text,
  municipio         text,
  provincia         text,
  horario           jsonb   not null default '{}'::jsonb,
  entrega_domicilio boolean not null default false,
  entrega_recogida  boolean not null default true,
  moneda            text    not null default 'CUP',
  moneda_alt        text,
  tasa_alt          numeric(12,4) check (tasa_alt is null or tasa_alt > 0),
  rubro             rubro_t not null default 'otro',
  activo            boolean not null default true,
  plan              text    not null default 'base',
  verificado        boolean not null default false,
  codigo_referido   text    not null unique
                      default upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),
  referido_por      uuid references negocios(id) on delete set null,
  creado_en         timestamptz not null default now(),
  -- una moneda alternativa sin tasa no se puede mostrar
  constraint moneda_alt_con_tasa check ((moneda_alt is null) = (tasa_alt is null))
);
create index negocios_directorio_idx on negocios (rubro, provincia) where activo;

create table perfiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  negocio_id uuid  not null references negocios(id) on delete cascade,
  rol        rol_t not null default 'dueno',
  creado_en  timestamptz not null default now()
);
create index perfiles_negocio_idx on perfiles (negocio_id);

-- ─────────────────────────────────────────────────────────────
-- Catálogo
-- ─────────────────────────────────────────────────────────────
create table categorias (
  id         uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios(id) on delete cascade,
  slug       text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  nombre     text not null,
  orden      int  not null default 0,
  unique (negocio_id, slug)
);

create table productos (
  id              uuid primary key default gen_random_uuid(),
  negocio_id      uuid not null references negocios(id) on delete cascade,
  categoria_id    uuid references categorias(id) on delete set null,
  slug            text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  nombre          text not null check (length(trim(nombre)) > 0),
  descripcion     text,
  precio_base     numeric(12,2) not null check (precio_base >= 0),
  -- solo tiene sentido si es mayor: de ahí sale el "Ahorra X%"
  precio_anterior numeric(12,2) check (precio_anterior is null or precio_anterior > precio_base),
  destacado       boolean not null default false,
  imagenes        text[]  not null default '{}',   -- public_id de Cloudinary, nunca URLs
  activo          boolean not null default true,
  orden           int     not null default 0,
  creado_en       timestamptz not null default now(),
  busqueda tsvector generated always as (
    to_tsvector('spanish',
      public.unaccent_inm(coalesce(nombre,'') || ' ' || coalesce(descripcion,'')))
  ) stored,
  unique (negocio_id, slug)
);
create index productos_busqueda_idx  on productos using gin (busqueda);
create index productos_catalogo_idx  on productos (negocio_id, orden) where activo;
create index productos_categoria_idx on productos (categoria_id);

-- El stock vive SIEMPRE aquí, nunca en productos. Una sola ruta de código.
create table variantes (
  id            uuid primary key default gen_random_uuid(),
  producto_id   uuid not null references productos(id) on delete cascade,
  nombre        text not null default 'Único',
  precio_delta  numeric(12,2) not null default 0,
  stock         int  not null default 0 check (stock >= 0),
  stock_minimo  int  not null default 0 check (stock_minimo >= 0),
  activo        boolean not null default true,
  orden         int  not null default 0,
  unique (producto_id, nombre)
);
create index variantes_producto_idx on variantes (producto_id);

-- Todo producto nace con una variante. Sin esto habría productos incomprables.
create or replace function _variante_por_defecto() returns trigger
language plpgsql as $$
begin
  insert into variantes (producto_id, nombre) values (new.id, 'Único');
  return new;
end $$;
create trigger productos_variante_por_defecto
  after insert on productos for each row execute function _variante_por_defecto();

-- ...y nunca se queda sin ninguna.
create or replace function _proteger_ultima_variante() returns trigger
language plpgsql as $$
begin
  if (select count(*) from variantes where producto_id = old.producto_id) <= 1 then
    raise exception 'Un producto no puede quedarse sin variantes';
  end if;
  return old;
end $$;
create trigger variantes_proteger_ultima
  before delete on variantes for each row execute function _proteger_ultima_variante();

-- ─────────────────────────────────────────────────────────────
-- Pedidos
-- ─────────────────────────────────────────────────────────────
create table pedidos (
  id               uuid primary key default gen_random_uuid(),
  negocio_id       uuid not null references negocios(id) on delete cascade,
  cliente_nombre   text not null,
  cliente_telefono text not null,
  nota             text,
  entrega          entrega_t not null default 'recogida',
  total            numeric(12,2) not null check (total >= 0),
  estado           estado_pedido_t not null default 'nuevo',
  creado_en        timestamptz not null default now()
);
create index pedidos_negocio_idx on pedidos (negocio_id, creado_en desc);

create table pedido_items (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null references pedidos(id) on delete cascade,
  -- si el producto se borra mañana, el pedido de hoy sigue siendo legible
  variante_id     uuid references variantes(id) on delete set null,
  nombre_snapshot text not null,
  precio_snapshot numeric(12,2) not null,
  cantidad        int not null check (cantidad > 0)
);
create index pedido_items_pedido_idx on pedido_items (pedido_id);

create table push_subs (
  id         uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  creado_en  timestamptz not null default now()
);
create index push_subs_negocio_idx on push_subs (negocio_id);

-- ─────────────────────────────────────────────────────────────
-- Alta de negocio: negocio + perfil en una transacción.
-- Así no hace falta una política de INSERT abierta sobre negocios.
-- ─────────────────────────────────────────────────────────────
create or replace function crear_negocio(
  p_slug     text,
  p_nombre   text,
  p_whatsapp text,
  p_rubro    rubro_t default 'otro',
  p_referido text    default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_negocio  uuid;
  v_referido uuid;
begin
  if auth.uid() is null then
    raise exception 'Hay que iniciar sesión';
  end if;
  if exists (select 1 from perfiles where id = auth.uid()) then
    raise exception 'Esta cuenta ya tiene un negocio';
  end if;

  if p_referido is not null then
    select id into v_referido from negocios where codigo_referido = upper(trim(p_referido));
  end if;

  insert into negocios (slug, nombre, whatsapp, rubro, referido_por)
  values (lower(trim(p_slug)), trim(p_nombre), trim(p_whatsapp), p_rubro, v_referido)
  returning id into v_negocio;

  insert into perfiles (id, negocio_id, rol) values (auth.uid(), v_negocio, 'dueno');
  return v_negocio;
end $$;

-- ─────────────────────────────────────────────────────────────
-- crear_pedido: valida, bloquea, descuenta y crea. Todo o nada.
-- Descontar stock desde el navegador es una condición de carrera:
-- dos compradores a la vez venden 3 unidades de 2.
-- ─────────────────────────────────────────────────────────────
create or replace function crear_pedido(
  p_negocio_slug     text,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_items            jsonb,
  p_entrega          entrega_t default 'recogida',
  p_nota             text      default null
) returns table (pedido_id uuid, total numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_negocio uuid;
  v_pedido  uuid;
  v_total   numeric(12,2) := 0;
  v_item    jsonb;
  v_cant    int;
  v_var     record;
begin
  if coalesce(trim(p_cliente_nombre), '') = '' then
    raise exception 'Falta el nombre del cliente';
  end if;
  if coalesce(trim(p_cliente_telefono), '') = '' then
    raise exception 'Falta el teléfono del cliente';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido está vacío';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Demasiados artículos en un pedido';
  end if;

  select id into v_negocio from negocios where slug = p_negocio_slug and activo;
  if v_negocio is null then
    raise exception 'Tienda no encontrada';
  end if;

  insert into pedidos (negocio_id, cliente_nombre, cliente_telefono, nota, entrega, total)
  values (v_negocio, trim(p_cliente_nombre), trim(p_cliente_telefono),
          nullif(trim(p_nota), ''), coalesce(p_entrega, 'recogida'), 0)
  returning id into v_pedido;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_cant := nullif(v_item->>'cantidad', '')::int;
    if v_cant is null or v_cant <= 0 then
      raise exception 'Cantidad inválida';
    end if;

    -- FOR UPDATE: aquí es donde se evita vender dos veces la misma unidad
    select v.id, v.stock, v.nombre as v_nombre, p.nombre as p_nombre,
           (p.precio_base + v.precio_delta) as precio
      into v_var
    from variantes v
    join productos p on p.id = v.producto_id
    where v.id = nullif(v_item->>'variante_id', '')::uuid
      and p.negocio_id = v_negocio
      and p.activo and v.activo
    for update of v;

    if not found then
      raise exception 'Producto no disponible';
    end if;
    if v_var.stock < v_cant then
      raise exception 'Sin stock suficiente de % (%): quedan %',
        v_var.p_nombre, v_var.v_nombre, v_var.stock;
    end if;

    update variantes set stock = stock - v_cant where id = v_var.id;

    insert into pedido_items (pedido_id, variante_id, nombre_snapshot, precio_snapshot, cantidad)
    values (v_pedido, v_var.id,
            v_var.p_nombre || case when v_var.v_nombre = 'Único'
                                   then '' else ' — ' || v_var.v_nombre end,
            v_var.precio, v_cant);

    v_total := v_total + v_var.precio * v_cant;
  end loop;

  update pedidos set total = v_total where id = v_pedido;
  return query select v_pedido, v_total;
end $$;
