-- =====================================================
-- VELTRO - Inicialización del Master
-- =====================================================

-- Crear base de datos
CREATE DATABASE IF NOT EXISTS veltro_prod;
USE veltro_prod;

-- =====================================================
-- TABLAS
-- =====================================================

CREATE TABLE IF NOT EXISTS usuarios (
  id VARCHAR(20) PRIMARY KEY,
  nombre VARCHAR(50),
  apellido VARCHAR(50),
  correo VARCHAR(100) UNIQUE NOT NULL,
  contrasena VARCHAR(255) NOT NULL,
  rol ENUM('jugador', 'administrador') NOT NULL,
  estado ENUM('activo', 'inactivo') DEFAULT 'activo'
);

CREATE TABLE IF NOT EXISTS equipos (
  id_equipo INT PRIMARY KEY AUTO_INCREMENT,
  nombre VARCHAR(100) NOT NULL,
  logo VARCHAR(255),
  color VARCHAR(50),
  estado ENUM('activo', 'inactivo') DEFAULT 'activo'
);

CREATE TABLE IF NOT EXISTS equipos_usuarios (
  id_equipo INT,
  id_usuario VARCHAR(20),
  posicion VARCHAR(30),
  estado ENUM('activo', 'inactivo') DEFAULT 'activo',
  PRIMARY KEY (id_equipo, id_usuario),
  FOREIGN KEY (id_equipo) REFERENCES equipos(id_equipo),
  FOREIGN KEY (id_usuario) REFERENCES usuarios(id)
);

CREATE TABLE IF NOT EXISTS ligas (
  id_liga INT PRIMARY KEY AUTO_INCREMENT,
  nombre VARCHAR(100),
  formato VARCHAR(50),
  fecha_inicio DATE,
  fecha_fin DATE,
  estado_liga ENUM('programada','en curso','finalizada','cancelada'),
  estado ENUM('activo','inactivo') DEFAULT 'activo'
);

CREATE TABLE IF NOT EXISTS canchas (
  id_cancha INT PRIMARY KEY AUTO_INCREMENT,
  nombre VARCHAR(100),
  direccion VARCHAR(255),
  horarios TEXT,
  estado ENUM('activo','inactivo') DEFAULT 'activo'
);

CREATE TABLE IF NOT EXISTS juegos (
  id_juego INT PRIMARY KEY AUTO_INCREMENT,
  id_equipo_local INT,
  id_equipo_visitante INT,
  id_cancha INT,
  fecha DATETIME,
  estado_juego ENUM('programado','jugado','suspendido'),
  resultado_local INT,
  resultado_visitante INT,
  estado ENUM('activo','inactivo') DEFAULT 'activo',
  FOREIGN KEY (id_equipo_local) REFERENCES equipos(id_equipo),
  FOREIGN KEY (id_equipo_visitante) REFERENCES equipos(id_equipo),
  FOREIGN KEY (id_cancha) REFERENCES canchas(id_cancha)
);

-- =====================================================
-- DATOS DE PRUEBA
-- =====================================================

INSERT INTO equipos (nombre, logo, color, estado) VALUES
('Los Tigres', 'tigres.png', '#FF6B35', 'activo'),
('Águilas FC', 'aguilas.png', '#004E89', 'activo'),
('Leones United', 'leones.png', '#F77F00', 'activo');

INSERT INTO usuarios (id, nombre, apellido, correo, contrasena, rol, estado) VALUES
('USR001', 'Mateo', 'Lopez', 'mlopez@veltro.uy', 'hashed_pass_1', 'administrador', 'activo'),
('USR002', 'Fermin', 'Martinez', 'fmartinez@veltro.uy', 'hashed_pass_2', 'jugador', 'activo'),
('USR003', 'Nahuel', 'Galego', 'ngalego@veltro.uy', 'hashed_pass_3', 'jugador', 'activo');

INSERT INTO equipos_usuarios (id_equipo, id_usuario, posicion, estado) VALUES
(1, 'USR001', 'Presidente', 'activo'),
(1, 'USR002', 'Delantero', 'activo'),
(2, 'USR003', 'Volante', 'activo');

INSERT INTO ligas (nombre, formato, fecha_inicio, fecha_fin, estado_liga, estado) VALUES
('Liga Apertura 2026', 'todos contra todos', '2026-03-01', '2026-06-30', 'en curso', 'activo');

-- =====================================================
-- USUARIOS DE SISTEMA
-- =====================================================

-- Usuario replicator (para replicación)
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'Replicator_V3ltr0_2025!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';

-- Usuario exporter (para Prometheus)
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED WITH mysql_native_password BY 'Exp0rt3r_2025!';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

-- Crear usuario backup
CREATE USER IF NOT EXISTS 'backup_user'@'%' IDENTIFIED WITH mysql_native_password BY 'B4ckup_V3ltr0_2025!';
GRANT SELECT, LOCK TABLES, SHOW VIEW, PROCESS, RELOAD, REPLICATION CLIENT ON *.* TO 'backup_user'@'%';

FLUSH PRIVILEGES;