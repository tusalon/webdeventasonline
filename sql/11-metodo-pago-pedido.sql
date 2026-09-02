-- VentasRoma — el método de pago se guarda dentro de crear_pedido
--
-- El bug: el carrito llamaba a crear_pedido y DESPUÉS hacía un update sobre
-- `pedidos` para anotar el método. Pero `anon` no tiene permiso de UPDATE sobre
-- esa tabla —y no debe tenerlo, o cualquiera editaría pedidos ajenos—, así que
-- el update fallaba con 42501. Como el resultado no se comprobaba, fallaba en
-- silencio: el comprador elegía Zelle, lo veía en el mensaje de WhatsApp, y el
-- pedido quedaba sin método en el panel.
--
-- Tres pedidos reales entraron así antes de detectarlo.
--
-- El arreglo NO es abrir permisos: es que lo escriba la propia función, que es
-- SECURITY DEFINER y ya está escribiendo el pedido.
--
-- La MONEDA no la manda el cliente: se saca de la configuración del negocio.
-- Si viniera de fuera, cualquiera podría declarar que paga 100 CUP una compra
-- de 100 USD.

begin;

drop function if exists crear_pedido(text, text, text, jsonb, entrega_t, text);

create function crear_pedido(
  p_negocio_slug     text,
  p_cliente_nombre   text,
  p_cliente_telefono text,
  p_items            jsonb,
  p_entrega          entrega_t default 'recogida',
  p_nota             text      default null,
  p_metodo_pago      text      default null
) returns table (pedido_id uuid, total numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_negocio uuid;
  v_pedido  uuid;
  v_total   numeric(12,2) := 0;
  v_item    jsonb;
  v_cant    int;
  v_var     record;
  v_moneda  text;
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

  -- Una tienda sin aprobar no vende, aunque alguien tenga el enlace directo.
  select id into v_negocio
  from negocios where slug = p_negocio_slug and activo and aprobado;
  if v_negocio is null then
    raise exception 'Tienda no encontrada';
  end if;

  -- El método tiene que ser uno de los que ESE negocio acepta, y la moneda
  -- sale de su configuración, no de lo que mande el navegador.
  if p_metodo_pago is not null then
    select m->>'moneda' into v_moneda
    from negocios n, jsonb_array_elements(n.metodos_pago) m
    where n.id = v_negocio and m->>'tipo' = p_metodo_pago;

    if v_moneda is null then
      raise exception 'Esa tienda no acepta ese método de pago';
    end if;
    v_moneda := upper(v_moneda);
  end if;

  insert into pedidos (negocio_id, cliente_nombre, cliente_telefono, nota,
                       entrega, total, metodo_pago, moneda_pago)
  values (v_negocio, trim(p_cliente_nombre), trim(p_cliente_telefono),
          nullif(trim(p_nota), ''), coalesce(p_entrega, 'recogida'), 0,
          p_metodo_pago, v_moneda)
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

revoke all on function crear_pedido(text, text, text, jsonb, entrega_t, text, text) from public;
grant execute on function crear_pedido(text, text, text, jsonb, entrega_t, text, text)
  to anon, authenticated;   -- el comprador no tiene cuenta

commit;

-- ─────────────────────────────────────────────────────────────
-- Los tres pedidos que ya entraron se quedan en null a propósito:
-- no sabemos cómo pagaron, e inventarlo sería peor que dejarlo vacío.
-- ─────────────────────────────────────────────────────────────
select cliente_nombre, total, metodo_pago, moneda_pago, creado_en
from pedidos order by creado_en desc limit 5;
