-- VentasRoma — datos demo + verificación de aislamiento
--
-- Esto no es "datos de ejemplo bonitos": es la prueba de que el negocio A no
-- puede ver ni tocar lo PRIVADO de B. Si esta parte no pasa, no se escribe ni
-- una línea de app. Se ejecuta entero en el editor SQL de Supabase.
--
-- Qué es privado y qué no:
--   PÚBLICO  → el catálogo activo (productos, variantes, categorías, negocio).
--              Cualquiera lo ve, con o sin sesión. Es el sentido de la tienda:
--              el comprador llega desde un link de Instagram y no tiene cuenta.
--   PRIVADO  → pedidos, teléfonos de clientes, perfiles, suscripciones push,
--              y todo lo que el dueño tenga desactivado u oculto.
--
-- Idempotente: se puede volver a lanzar las veces que haga falta.

begin;

-- ─────────────────────────────────────────────────────────────
-- Limpieza de una ejecución anterior
-- ─────────────────────────────────────────────────────────────
delete from negocios  where slug in ('demo-ropa', 'demo-comida');
delete from auth.users where email in ('demo-ropa@ventasroma.test', 'demo-comida@ventasroma.test');

-- ─────────────────────────────────────────────────────────────
-- Dos usuarios de prueba (hacen falta por la FK de perfiles)
-- ─────────────────────────────────────────────────────────────
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'demo-ropa@ventasroma.test', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}'),
  ('bbbbbbbb-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'demo-comida@ventasroma.test', '', now(), now(), now(),
   '{"provider":"email","providers":["email"]}', '{}');

-- ─────────────────────────────────────────────────────────────
-- Negocio A — ropa (con tallas)
-- ─────────────────────────────────────────────────────────────
-- Precios en USD con equivalente en CUP: 1 USD = 420 CUP. En este sentido y
-- no al reves, que es como estaba antes de que `tasas` sustituyera a tasa_alt.
insert into negocios (id, slug, nombre, whatsapp, rubro, provincia, municipio,
                      moneda, moneda_alt, tasas, entrega_domicilio)
values ('11111111-0000-4000-8000-000000000001', 'demo-ropa', 'Boutique Demo',
        '+5355551111', 'ropa', 'La Habana', 'Centro Habana',
        'USD', 'CUP', '{"CUP": 420}'::jsonb, true);

insert into perfiles (id, negocio_id)
values ('aaaaaaaa-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001');

insert into categorias (id, negocio_id, slug, nombre)
values ('c1111111-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000001', 'vestidos', 'Vestidos');

insert into productos (id, negocio_id, categoria_id, slug, nombre, descripcion,
                       precio_base, precio_anterior, destacado)
values ('d1111111-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000001',
        'c1111111-0000-4000-8000-000000000001',
        'vestido-rojo', 'Vestido rojo', 'Algodón, manga corta', 4000, 5000, true);

-- El trigger ya creó la variante "Único"; en ropa se sustituye por tallas.
insert into variantes (producto_id, nombre, stock, stock_minimo, orden) values
  ('d1111111-0000-4000-8000-000000000001', 'S', 5, 2, 1),
  ('d1111111-0000-4000-8000-000000000001', 'M', 3, 2, 2),
  ('d1111111-0000-4000-8000-000000000001', 'L', 0, 2, 3);
delete from variantes
 where producto_id = 'd1111111-0000-4000-8000-000000000001' and nombre = 'Único';

-- ─────────────────────────────────────────────────────────────
-- Negocio B — comida (sin variantes: se queda con "Único")
-- ─────────────────────────────────────────────────────────────
insert into negocios (id, slug, nombre, whatsapp, rubro, provincia, municipio)
values ('22222222-0000-4000-8000-000000000002', 'demo-comida', 'Dulcería Demo',
        '+5355552222', 'alimentos', 'La Habana', 'Vedado');

insert into perfiles (id, negocio_id)
values ('bbbbbbbb-0000-4000-8000-000000000002', '22222222-0000-4000-8000-000000000002');

insert into productos (id, negocio_id, slug, nombre, precio_base)
values ('d2222222-0000-4000-8000-000000000002',
        '22222222-0000-4000-8000-000000000002', 'cake-vainilla', 'Cake de vainilla', 2500);

update variantes set stock = 10, stock_minimo = 2
 where producto_id = 'd2222222-0000-4000-8000-000000000002';

-- Producto oculto de B: esto SÍ es privado y nadie de fuera debe verlo.
insert into productos (id, negocio_id, slug, nombre, precio_base, activo)
values ('d2222222-0000-4000-8000-000000000003',
        '22222222-0000-4000-8000-000000000002', 'receta-secreta', 'Receta secreta', 9999, false);

-- Un pedido de B, para comprobar que A no ve ni el pedido ni el teléfono.
insert into pedidos (negocio_id, cliente_nombre, cliente_telefono, total)
values ('22222222-0000-4000-8000-000000000002', 'Cliente de B', '+5355550000', 2500);

commit;

-- ═════════════════════════════════════════════════════════════
-- VERIFICACIÓN — falla ruidosamente si algo no cuadra
-- ═════════════════════════════════════════════════════════════
do $$
declare
  n     int;
  v_rol text;
  v_neg uuid;
  v_var uuid;
  v_tot numeric;
  v_ped uuid;
begin
  -- ══ 0. La prueba tiene que ser una prueba ══════════════════
  -- El dueño de las tablas se salta RLS. Si el cambio de rol no surte
  -- efecto, todo lo de abajo pasaría sin comprobar absolutamente nada.
  set local role authenticated;
  set local "request.jwt.claims" =
    '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}';

  select current_user into v_rol;
  if v_rol <> 'authenticated' then
    raise exception 'FALLO: el rol es "%", no "authenticated". La prueba no valdría nada', v_rol;
  end if;

  select auth_negocio_id() into v_neg;
  if v_neg is distinct from '11111111-0000-4000-8000-000000000001'::uuid then
    raise exception 'FALLO: auth_negocio_id() devuelve %, no el negocio A', v_neg;
  end if;

  -- ══ 1. Lo PRIVADO de B es invisible para A ═════════════════
  select count(*) into n from pedidos where negocio_id = '22222222-0000-4000-8000-000000000002';
  if n <> 0 then raise exception 'FALLO: A ve % pedidos de B (con teléfonos de sus clientes)', n; end if;

  select count(*) into n from perfiles where negocio_id = '22222222-0000-4000-8000-000000000002';
  if n <> 0 then raise exception 'FALLO: A ve los perfiles de B'; end if;

  select count(*) into n from push_subs where negocio_id = '22222222-0000-4000-8000-000000000002';
  if n <> 0 then raise exception 'FALLO: A ve las suscripciones push de B'; end if;

  -- Lo que B tiene desactivado tampoco se ve desde fuera.
  select count(*) into n from productos where slug = 'receta-secreta';
  if n <> 0 then raise exception 'FALLO: A ve un producto OCULTO de B'; end if;

  -- ══ 2. Lo PÚBLICO sí se ve, y es lo correcto ═══════════════
  -- El catálogo activo de B es público a propósito: el comprador llega sin
  -- cuenta desde un link. Que A lo vea no es una fuga, es la tienda.
  select count(*) into n from productos where slug = 'cake-vainilla';
  if n <> 1 then raise exception 'FALLO: el catálogo público de B no se ve'; end if;

  select count(*) into n from productos where negocio_id = '11111111-0000-4000-8000-000000000001';
  if n = 0 then raise exception 'FALLO: A no ve sus propios productos'; end if;

  -- ══ 3. A no puede ESCRIBIR en B ════════════════════════════
  begin
    insert into productos (negocio_id, slug, nombre, precio_base)
    values ('22222222-0000-4000-8000-000000000002', 'colado', 'Colado', 1);
    raise exception 'FALLO: A pudo insertar un producto en B';
  exception when insufficient_privilege then null;
  end;

  update productos set precio_base = 1 where slug = 'cake-vainilla';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: A cambió el precio de un producto de B'; end if;

  update variantes set stock = 999
   where producto_id = 'd2222222-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: A modificó el stock de B'; end if;

  delete from productos where slug = 'cake-vainilla';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: A borró un producto de B'; end if;

  -- ══ 4. Sin sesión: catálogo sí, datos de clientes no ═══════
  reset role;
  set local role anon;
  set local "request.jwt.claims" = '{"role":"anon"}';

  select current_user into v_rol;
  if v_rol <> 'anon' then
    raise exception 'FALLO: el rol es "%", no "anon"', v_rol;
  end if;

  select count(*) into n from productos;
  if n < 2 then raise exception 'FALLO: el catálogo público no se ve sin login'; end if;

  select count(*) into n from pedidos;
  if n <> 0 then raise exception 'FALLO: los pedidos se leen SIN SESIÓN'; end if;

  select count(*) into n from perfiles;
  if n <> 0 then raise exception 'FALLO: los perfiles se leen SIN SESIÓN'; end if;

  -- ══ 5. Stock: descuenta lo pedido, una sola vez ════════════
  reset role;
  select id into v_var from variantes
   where producto_id = 'd1111111-0000-4000-8000-000000000001' and nombre = 'M';

  set local role anon;
  set local "request.jwt.claims" = '{"role":"anon"}';

  select p.pedido_id, p.total into v_ped, v_tot
  from crear_pedido('demo-ropa', 'Ana', '+5355559999',
                    jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 3))) p;

  if v_tot <> 12000 then raise exception 'FALLO: total % en vez de 12000', v_tot; end if;

  reset role;
  select stock into n from variantes where id = v_var;
  if n <> 0 then raise exception 'FALLO: quedan % de la talla M, deberían ser 0', n; end if;

  -- ══ 6. Sin stock no hay pedido, ni a medias ════════════════
  set local role anon;
  set local "request.jwt.claims" = '{"role":"anon"}';
  begin
    perform crear_pedido('demo-ropa', 'Beto', '+5355558888',
                         jsonb_build_array(jsonb_build_object('variante_id', v_var, 'cantidad', 1)));
    raise exception 'FALLO: se aceptó un pedido sin stock';
  exception when raise_exception then
    if sqlerrm like 'FALLO:%' then raise; end if;
  end;

  reset role;
  select count(*) into n from pedidos where cliente_nombre = 'Beto';
  if n <> 0 then raise exception 'FALLO: quedó un pedido huérfano tras fallar el stock'; end if;

  -- ══ 7. Un producto no puede quedarse sin variantes ═════════
  begin
    delete from variantes where producto_id = 'd2222222-0000-4000-8000-000000000002';
    raise exception 'FALLO: se borró la última variante de un producto';
  exception when raise_exception then
    if sqlerrm like 'FALLO:%' then raise; end if;
  end;

  -- ══ 8. Buscador: acentos y mayúsculas dan igual ════════════
  select count(*) into n from productos
   where busqueda @@ plainto_tsquery('spanish', public.unaccent_inm('VAINILLA'));
  if n <> 1 then raise exception 'FALLO: el buscador no encuentra "vainilla"'; end if;

  raise notice 'OK — aislamiento, escritura, stock, variantes y buscador verificados';
end $$;
