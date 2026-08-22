-- VentasRoma — Row Level Security
--
-- Esta es LA frontera de confianza de la app. Un fallo aquí y el negocio A ve
-- el inventario, los pedidos y los teléfonos de los clientes de B.
-- Por eso se escribe a mano y se verifica con 03-datos-demo.sql antes de
-- conectar Lovable. No dejar que ninguna herramienta lo regenere.

-- El negocio del usuario autenticado. SECURITY DEFINER para poder leer
-- perfiles sin que la propia política de perfiles se muerda la cola.
create or replace function auth_negocio_id() returns uuid
language sql stable security definer set search_path = public as $$
  select negocio_id from perfiles where id = auth.uid()
$$;

alter table negocios     enable row level security;
alter table perfiles     enable row level security;
alter table categorias   enable row level security;
alter table productos    enable row level security;
alter table variantes    enable row level security;
alter table pedidos      enable row level security;
alter table pedido_items enable row level security;
alter table push_subs    enable row level security;

-- ─────────────────────────────────────────────────────────────
-- Negocios
-- ─────────────────────────────────────────────────────────────
-- La tienda tiene que verse sin login.
create policy negocios_publico on negocios
  for select using (activo);

-- El dueño ve el suyo aunque esté desactivado (si no, no podría reactivarlo).
create policy negocios_propio_ver on negocios
  for select to authenticated using (id = auth_negocio_id());

create policy negocios_propio_editar on negocios
  for update to authenticated
  using (id = auth_negocio_id()) with check (id = auth_negocio_id());

-- Sin política de INSERT ni DELETE a propósito: el alta va por crear_negocio(),
-- que crea negocio + perfil en una transacción. Una política de insert abierta
-- dejaría crear negocios sueltos y sin dueño.

-- ─────────────────────────────────────────────────────────────
-- Perfiles — solo se ven los del propio negocio. Nunca públicos.
-- ─────────────────────────────────────────────────────────────
create policy perfiles_propio on perfiles
  for select to authenticated using (negocio_id = auth_negocio_id());

-- ─────────────────────────────────────────────────────────────
-- Categorías
-- ─────────────────────────────────────────────────────────────
create policy categorias_publico on categorias
  for select using (
    exists (select 1 from negocios n where n.id = categorias.negocio_id and n.activo)
  );

create policy categorias_propio on categorias
  for all to authenticated
  using (negocio_id = auth_negocio_id()) with check (negocio_id = auth_negocio_id());

-- ─────────────────────────────────────────────────────────────
-- Productos
-- ─────────────────────────────────────────────────────────────
create policy productos_publico on productos
  for select using (
    activo and exists (select 1 from negocios n where n.id = productos.negocio_id and n.activo)
  );

create policy productos_propio on productos
  for all to authenticated
  using (negocio_id = auth_negocio_id()) with check (negocio_id = auth_negocio_id());

-- ─────────────────────────────────────────────────────────────
-- Variantes — el negocio_id llega por el producto
-- ─────────────────────────────────────────────────────────────
create policy variantes_publico on variantes
  for select using (
    activo and exists (
      select 1 from productos p join negocios n on n.id = p.negocio_id
      where p.id = variantes.producto_id and p.activo and n.activo
    )
  );

create policy variantes_propio on variantes
  for all to authenticated
  using (exists (
    select 1 from productos p
    where p.id = variantes.producto_id and p.negocio_id = auth_negocio_id()
  ))
  with check (exists (
    select 1 from productos p
    where p.id = variantes.producto_id and p.negocio_id = auth_negocio_id()
  ));

-- ─────────────────────────────────────────────────────────────
-- Pedidos — SIN lectura pública. Llevan nombre y teléfono de clientes.
-- El alta va solo por crear_pedido() (SECURITY DEFINER): no hay política
-- de INSERT, así que nadie puede inyectar pedidos ni saltarse el stock.
-- ─────────────────────────────────────────────────────────────
create policy pedidos_propio_ver on pedidos
  for select to authenticated using (negocio_id = auth_negocio_id());

create policy pedidos_propio_editar on pedidos
  for update to authenticated
  using (negocio_id = auth_negocio_id()) with check (negocio_id = auth_negocio_id());

create policy pedido_items_propio_ver on pedido_items
  for select to authenticated using (
    exists (select 1 from pedidos pe
            where pe.id = pedido_items.pedido_id and pe.negocio_id = auth_negocio_id())
  );

-- ─────────────────────────────────────────────────────────────
-- Suscripciones push
-- ─────────────────────────────────────────────────────────────
create policy push_subs_propio on push_subs
  for all to authenticated
  using (negocio_id = auth_negocio_id()) with check (negocio_id = auth_negocio_id());

-- ─────────────────────────────────────────────────────────────
-- Permisos de las funciones
-- ─────────────────────────────────────────────────────────────
revoke all on function crear_pedido(text, text, text, jsonb, entrega_t, text) from public;
grant execute on function crear_pedido(text, text, text, jsonb, entrega_t, text)
  to anon, authenticated;   -- el comprador no tiene cuenta

revoke all on function crear_negocio(text, text, text, rubro_t, text) from public;
grant execute on function crear_negocio(text, text, text, rubro_t, text) to authenticated;

revoke all on function auth_negocio_id() from public;
grant execute on function auth_negocio_id() to authenticated;

-- Cinturón además de tirantes: aunque una política se relaje por error,
-- anon no tiene permiso de escritura en ninguna tabla.
revoke insert, update, delete on all tables in schema public from anon;
