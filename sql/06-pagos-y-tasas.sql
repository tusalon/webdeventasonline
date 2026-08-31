-- VentasRoma — métodos de pago y tasas de cambio
--
-- Dos cambios que van juntos porque uno no funciona sin el otro:
--
--   1. Un negocio puede cobrar por Transfermóvil (CUP), Zelle (USD) y Bizum
--      (EUR) a la vez. Cada método necesita saber en qué moneda cobra.
--   2. Para eso hace falta más de una tasa. El par moneda_alt + tasa_alt solo
--      permitía una moneda alternativa, y encima invitaba a equivocarse: hay
--      tiendas con la moneda y la alternativa al revés.
--
-- `tasas` sustituye a `tasa_alt`: un mapa {MONEDA: cuánto vale 1 unidad de la
-- moneda del negocio en esa moneda}. Con moneda = USD y tasas = {"CUP": 675},
-- un producto de 18 USD son 18 × 675 = 12.150 CUP.

-- ─────────────────────────────────────────────────────────────
-- 1. Normalizar los códigos de moneda
-- ─────────────────────────────────────────────────────────────
-- Hay tiendas con "Usd" y "Cup" escritos a mano. Los códigos van en mayúscula
-- siempre, o cada comparación en el código tiene que acordarse de normalizar.
update negocios set moneda = upper(trim(moneda)) where moneda is not null;
update negocios set moneda_alt = upper(trim(moneda_alt)) where moneda_alt is not null;

-- ─────────────────────────────────────────────────────────────
-- 2. Mapa de tasas
-- ─────────────────────────────────────────────────────────────
alter table negocios add column if not exists tasas jsonb not null default '{}'::jsonb;

-- Arrastra la tasa que ya existía, para no perder lo configurado.
update negocios
set tasas = jsonb_build_object(moneda_alt, tasa_alt)
where moneda_alt is not null and tasa_alt is not null and tasas = '{}'::jsonb;

-- tasa_alt se va: el mapa es ahora la única fuente. Dejar las dos habría sido
-- dos verdades que se contradicen en cuanto alguien edite una.
alter table negocios drop constraint if exists moneda_alt_con_tasa;
alter table negocios drop column if exists tasa_alt;

-- moneda_alt se queda, pero cambia de significado: ya no trae su tasa, solo
-- dice cuál de las tasas se muestra en el catálogo.
comment on column negocios.moneda_alt is
  'Qué moneda se muestra como equivalente en el catálogo. Su tasa sale de `tasas`.';
comment on column negocios.tasas is
  'Cuánto vale 1 unidad de `moneda` en cada otra moneda. {"CUP": 675} con moneda USD => 1 USD = 675 CUP.';

-- La alternativa del catálogo tiene que tener tasa, o se muestra un equivalente
-- inventado.
alter table negocios drop constraint if exists moneda_alt_con_su_tasa;
alter table negocios add constraint moneda_alt_con_su_tasa
  check (moneda_alt is null or tasas ? moneda_alt);

-- ─────────────────────────────────────────────────────────────
-- 3. Métodos de pago
-- ─────────────────────────────────────────────────────────────
-- jsonb y no una tabla: es configuración de cada negocio, nadie la consulta
-- entre negocios, y son siete entradas como mucho.
alter table negocios add column if not exists metodos_pago jsonb not null default '[]'::jsonb;

alter table negocios drop constraint if exists metodos_pago_es_lista;
alter table negocios add constraint metodos_pago_es_lista
  check (jsonb_typeof(metodos_pago) = 'array');

comment on column negocios.metodos_pago is
  'Array de {tipo, moneda, datos, red, nota}. Los datos NO se muestran en el catálogo público: solo al comprador que ya hizo un pedido.';

alter table pedidos add column if not exists metodo_pago text;
alter table pedidos add column if not exists moneda_pago text;

comment on column pedidos.moneda_pago is
  'Moneda del método elegido. Se guarda con el pedido porque las tasas cambian y el histórico no debe recalcularse.';

-- ─────────────────────────────────────────────────────────────
-- Repaso
-- ─────────────────────────────────────────────────────────────
select nombre, moneda, moneda_alt, tasas, metodos_pago from negocios order by nombre;
