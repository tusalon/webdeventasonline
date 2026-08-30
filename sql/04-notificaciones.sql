-- VentasRoma — avisos push al dueño
--
-- Se ejecuta después de 01, 02 y 03, cuando la Edge Function `notificar`
-- ya esté desplegada.
--
-- Por qué desde la base y no desde el navegador: si el aviso lo disparara el
-- cliente, dependería de que la página siga abierta y de que nadie manipule la
-- petición. Aquí va atado al dato que cambió: si hay pedido, hay aviso.

create extension if not exists pg_net with schema extensions;

-- ─────────────────────────────────────────────────────────────
-- Config privada: la URL de la función y su secreto compartido.
-- RLS activado y SIN NINGUNA POLÍTICA a propósito: así no se puede leer
-- desde la API con ninguna clave. Solo lo ven las funciones SECURITY
-- DEFINER, que se saltan RLS.
-- ─────────────────────────────────────────────────────────────
create table if not exists ajustes_internos (
  clave text primary key,
  valor text not null
);
alter table ajustes_internos enable row level security;
revoke all on ajustes_internos from anon, authenticated;

-- Rellenar a mano una sola vez (sustituye el secreto por uno tuyo):
--
--   insert into ajustes_internos (clave, valor) values
--     ('url_notificar', 'https://pzjhvvslhawszjrtxhih.supabase.co/functions/v1/notificar'),
--     ('secreto_notificar', 'PON_AQUI_UNA_CADENA_LARGA_Y_ALEATORIA')
--   on conflict (clave) do update set valor = excluded.valor;

create or replace function _avisar(
  p_tipo text, p_negocio uuid, p_titulo text, p_cuerpo text, p_url text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_url     text;
  v_secreto text;
begin
  select valor into v_url     from ajustes_internos where clave = 'url_notificar';
  select valor into v_secreto from ajustes_internos where clave = 'secreto_notificar';

  -- Sin configurar, no se avisa. Nunca se rompe la operación por esto:
  -- un pedido tiene que entrar aunque el aviso falle.
  if v_url is null or v_secreto is null then return; end if;

  -- Con => y no con :=. Dentro de PL/pgSQL, := choca con el operador de
  -- asignacion y la llamada se interpreta por POSICION: las cabeceras
  -- acababan enviandose como cuerpo y la funcion recibia basura.
  -- La firma es net.http_post(url, body, params, headers, timeout).
  perform net.http_post(
    url     => v_url,
    body    => jsonb_build_object(
                 'tipo', p_tipo, 'negocio_id', p_negocio,
                 'titulo', p_titulo, 'cuerpo', p_cuerpo, 'url', p_url),
    params  => '{}'::jsonb,
    headers => jsonb_build_object('Content-Type', 'application/json', 'x-secreto', v_secreto)
  );
exception when others then
  -- pg_net es asíncrono, pero si algo revienta aquí no puede tumbar el pedido.
  raise warning 'aviso no enviado: %', sqlerrm;
end $$;

-- ─────────────────────────────────────────────────────────────
-- Pedido nuevo
-- ─────────────────────────────────────────────────────────────
create or replace function _avisar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform _avisar(
    'pedido', new.negocio_id,
    'Pedido nuevo',
    new.cliente_nombre || ' — ' || round(new.total) || ' ' ||
      (select moneda from negocios where id = new.negocio_id),
    '/admin/pedidos');
  return new;
end $$;

drop trigger if exists pedidos_avisar on pedidos;
create trigger pedidos_avisar
  after insert on pedidos for each row execute function _avisar_pedido();

-- ─────────────────────────────────────────────────────────────
-- Stock bajo
--
-- Solo al CRUZAR el umbral hacia abajo. Sin esa condición, cada venta de un
-- producto ya bajo mandaría otro aviso y el dueño acabaría silenciándolos —
-- que es la forma de que un aviso deje de servir para nada.
-- ─────────────────────────────────────────────────────────────
create or replace function _avisar_stock() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_producto text;
  v_negocio  uuid;
begin
  if new.stock_minimo = 0 then return new; end if;
  if not (new.stock <= new.stock_minimo and old.stock > old.stock_minimo) then
    return new;
  end if;

  select p.nombre, p.negocio_id into v_producto, v_negocio
  from productos p where p.id = new.producto_id;

  perform _avisar(
    'stock', v_negocio,
    'Se está acabando',
    v_producto || case when new.nombre = 'Único' then '' else ' — ' || new.nombre end
      || ': quedan ' || new.stock,
    '/admin/inventario');
  return new;
end $$;

drop trigger if exists variantes_avisar_stock on variantes;
create trigger variantes_avisar_stock
  after update of stock on variantes for each row execute function _avisar_stock();
