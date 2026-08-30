-- VentasRoma — provincias y municipios de Cuba
--
-- Datos de referencia: no cambian y no los edita nadie desde la app.
-- Van en la base y no en el código para que el formulario de alta no tenga que
-- arrastrar 168 entradas antes de pintarse, y para poder reutilizarlos desde
-- cualquier app del ecosistema.
--
-- Orden de occidente a oriente, que es como los espera cualquiera que viva
-- allí. Alfabético sería correcto y se sentiría mal.

create table if not exists municipios (
  id        int generated always as identity primary key,
  provincia text not null,
  nombre    text not null,
  orden_pro int  not null,
  unique (provincia, nombre)
);
create index if not exists municipios_provincia_idx on municipios (orden_pro, nombre);

alter table municipios enable row level security;

-- Lectura pública: el formulario de alta se usa sin sesión iniciada.
drop policy if exists municipios_lectura on municipios;
create policy municipios_lectura on municipios for select using (true);

-- Nadie escribe aquí desde la API.
revoke insert, update, delete on municipios from anon, authenticated;

delete from municipios;

insert into municipios (provincia, nombre, orden_pro) values
-- 1. Pinar del Río (11)
('Pinar del Río','Consolación del Sur',1),('Pinar del Río','Guane',1),
('Pinar del Río','La Palma',1),('Pinar del Río','Los Palacios',1),
('Pinar del Río','Mantua',1),('Pinar del Río','Minas de Matahambre',1),
('Pinar del Río','Pinar del Río',1),('Pinar del Río','San Juan y Martínez',1),
('Pinar del Río','San Luis',1),('Pinar del Río','Sandino',1),
('Pinar del Río','Viñales',1),
-- 2. Artemisa (11)
('Artemisa','Alquízar',2),('Artemisa','Artemisa',2),('Artemisa','Bahía Honda',2),
('Artemisa','Bauta',2),('Artemisa','Caimito',2),('Artemisa','Candelaria',2),
('Artemisa','Guanajay',2),('Artemisa','Güira de Melena',2),('Artemisa','Mariel',2),
('Artemisa','San Antonio de los Baños',2),('Artemisa','San Cristóbal',2),
-- 3. La Habana (15)
('La Habana','Arroyo Naranjo',3),('La Habana','Boyeros',3),
('La Habana','Centro Habana',3),('La Habana','Cerro',3),('La Habana','Cotorro',3),
('La Habana','Diez de Octubre',3),('La Habana','Guanabacoa',3),
('La Habana','Habana del Este',3),('La Habana','Habana Vieja',3),
('La Habana','La Lisa',3),('La Habana','Marianao',3),('La Habana','Playa',3),
('La Habana','Plaza de la Revolución',3),('La Habana','Regla',3),
('La Habana','San Miguel del Padrón',3),
-- 4. Mayabeque (11)
('Mayabeque','Batabanó',4),('Mayabeque','Bejucal',4),('Mayabeque','Güines',4),
('Mayabeque','Jaruco',4),('Mayabeque','Madruga',4),('Mayabeque','Melena del Sur',4),
('Mayabeque','Nueva Paz',4),('Mayabeque','Quivicán',4),
('Mayabeque','San José de las Lajas',4),('Mayabeque','San Nicolás',4),
('Mayabeque','Santa Cruz del Norte',4),
-- 5. Matanzas (13)
('Matanzas','Calimete',5),('Matanzas','Cárdenas',5),('Matanzas','Ciénaga de Zapata',5),
('Matanzas','Colón',5),('Matanzas','Jagüey Grande',5),('Matanzas','Jovellanos',5),
('Matanzas','Limonar',5),('Matanzas','Los Arabos',5),('Matanzas','Martí',5),
('Matanzas','Matanzas',5),('Matanzas','Pedro Betancourt',5),('Matanzas','Perico',5),
('Matanzas','Unión de Reyes',5),
-- 6. Villa Clara (13)
('Villa Clara','Caibarién',6),('Villa Clara','Camajuaní',6),('Villa Clara','Cifuentes',6),
('Villa Clara','Corralillo',6),('Villa Clara','Encrucijada',6),
('Villa Clara','Manicaragua',6),('Villa Clara','Placetas',6),
('Villa Clara','Quemado de Güines',6),('Villa Clara','Ranchuelo',6),
('Villa Clara','Remedios',6),('Villa Clara','Sagua la Grande',6),
('Villa Clara','Santa Clara',6),('Villa Clara','Santo Domingo',6),
-- 7. Cienfuegos (8)
('Cienfuegos','Abreus',7),('Cienfuegos','Aguada de Pasajeros',7),
('Cienfuegos','Cienfuegos',7),('Cienfuegos','Cruces',7),('Cienfuegos','Cumanayagua',7),
('Cienfuegos','Palmira',7),('Cienfuegos','Rodas',7),
('Cienfuegos','Santa Isabel de las Lajas',7),
-- 8. Sancti Spíritus (8)
('Sancti Spíritus','Cabaiguán',8),('Sancti Spíritus','Fomento',8),
('Sancti Spíritus','Jatibonico',8),('Sancti Spíritus','La Sierpe',8),
('Sancti Spíritus','Sancti Spíritus',8),('Sancti Spíritus','Taguasco',8),
('Sancti Spíritus','Trinidad',8),('Sancti Spíritus','Yaguajay',8),
-- 9. Ciego de Ávila (10)
('Ciego de Ávila','Baraguá',9),('Ciego de Ávila','Bolivia',9),
('Ciego de Ávila','Chambas',9),('Ciego de Ávila','Ciego de Ávila',9),
('Ciego de Ávila','Ciro Redondo',9),('Ciego de Ávila','Florencia',9),
('Ciego de Ávila','Majagua',9),('Ciego de Ávila','Morón',9),
('Ciego de Ávila','Primero de Enero',9),('Ciego de Ávila','Venezuela',9),
-- 10. Camagüey (13)
('Camagüey','Camagüey',10),('Camagüey','Carlos Manuel de Céspedes',10),
('Camagüey','Esmeralda',10),('Camagüey','Florida',10),('Camagüey','Guáimaro',10),
('Camagüey','Jimaguayú',10),('Camagüey','Minas',10),('Camagüey','Najasa',10),
('Camagüey','Nuevitas',10),('Camagüey','Santa Cruz del Sur',10),
('Camagüey','Sibanicú',10),('Camagüey','Sierra de Cubitas',10),
('Camagüey','Vertientes',10),
-- 11. Las Tunas (8)
('Las Tunas','Amancio',11),('Las Tunas','Colombia',11),('Las Tunas','Jesús Menéndez',11),
('Las Tunas','Jobabo',11),('Las Tunas','Las Tunas',11),('Las Tunas','Majibacoa',11),
('Las Tunas','Manatí',11),('Las Tunas','Puerto Padre',11),
-- 12. Holguín (14)
('Holguín','Antilla',12),('Holguín','Báguanos',12),('Holguín','Banes',12),
('Holguín','Cacocum',12),('Holguín','Calixto García',12),('Holguín','Cueto',12),
('Holguín','Frank País',12),('Holguín','Gibara',12),('Holguín','Holguín',12),
('Holguín','Mayarí',12),('Holguín','Moa',12),('Holguín','Rafael Freyre',12),
('Holguín','Sagua de Tánamo',12),('Holguín','Urbano Noris',12),
-- 13. Granma (13)
('Granma','Bartolomé Masó',13),('Granma','Bayamo',13),('Granma','Buey Arriba',13),
('Granma','Campechuela',13),('Granma','Cauto Cristo',13),('Granma','Guisa',13),
('Granma','Jiguaní',13),('Granma','Manzanillo',13),('Granma','Media Luna',13),
('Granma','Niquero',13),('Granma','Pilón',13),('Granma','Río Cauto',13),
('Granma','Yara',13),
-- 14. Santiago de Cuba (9)
('Santiago de Cuba','Contramaestre',14),('Santiago de Cuba','Guamá',14),
('Santiago de Cuba','Julio Antonio Mella',14),('Santiago de Cuba','Palma Soriano',14),
('Santiago de Cuba','San Luis',14),('Santiago de Cuba','Santiago de Cuba',14),
('Santiago de Cuba','Segundo Frente',14),('Santiago de Cuba','Songo-La Maya',14),
('Santiago de Cuba','Tercer Frente',14),
-- 15. Guantánamo (10)
('Guantánamo','Baracoa',15),('Guantánamo','Caimanera',15),('Guantánamo','El Salvador',15),
('Guantánamo','Guantánamo',15),('Guantánamo','Imías',15),('Guantánamo','Maisí',15),
('Guantánamo','Manuel Tames',15),('Guantánamo','Niceto Pérez',15),
('Guantánamo','San Antonio del Sur',15),('Guantánamo','Yateras',15),
-- 16. Isla de la Juventud (municipio especial)
('Isla de la Juventud','Isla de la Juventud',16);

-- Repaso: deben salir 16 provincias y 168 municipios.
select count(distinct provincia) as provincias, count(*) as municipios from municipios;
