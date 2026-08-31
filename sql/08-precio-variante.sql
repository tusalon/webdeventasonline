-- VentasRoma — el precio de la variante pasa a ser absoluto
--
-- `precio_delta` significaba "cuánto MÁS que el precio base". Ningún dueño de
-- tienda piensa así: piensa "esta talla vale 80". El resultado es que escriben
-- el precio completo en un campo que significa diferencia, y el producto se
-- vende al doble.
--
-- Pasó dos veces con dos negocios distintos. Cuando el mismo error se repite,
-- el problema no es quien lo comete: es la abstracción.
--
-- Ahora `variantes.precio` es el precio de esa variante, o null para usar el
-- del producto. Es lo que el dueño ya creía que estaba escribiendo.

alter table variantes add column if not exists precio numeric(12,2)
  check (precio is null or precio >= 0);

comment on column variantes.precio is
  'Precio de esta variante. Null = usa productos.precio_base. Absoluto, no diferencia.';

-- ─────────────────────────────────────────────────────────────
-- Migración literal, sin interpretar intenciones
-- ─────────────────────────────────────────────────────────────
-- Se traslada lo que el sistema COBRA hoy, no lo que el dueño quiso poner.
-- Cambiar precios en silencio durante una migración es peor que dejar un
-- precio mal: al menos el error visible se puede corregir.
update variantes v
set precio = p.precio_base + v.precio_delta
from productos p
where p.id = v.producto_id
  and v.precio is null
  and v.precio_delta <> 0;

-- Las que no tenían diferencia se quedan en null y heredan el del producto.

alter table variantes drop column if exists precio_delta;

-- ─────────────────────────────────────────────────────────────
-- crear_pedido usa el precio nuevo
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
           coalesce(v.precio, p.precio_base) as precio
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

  perform _avisar_pedido_creado(v_pedido);

  return query select v_pedido, v_total;
end $$;

-- ─────────────────────────────────────────────────────────────
-- Repaso: lo que se cobra ahora por cada variante
-- ─────────────────────────────────────────────────────────────
select p.nombre as producto, p.precio_base, p.precio_anterior,
       v.nombre as variante, v.precio as precio_propio,
       coalesce(v.precio, p.precio_base) as se_cobra
from variantes v
join productos p on p.id = v.producto_id
order by p.nombre, v.orden, v.nombre;
