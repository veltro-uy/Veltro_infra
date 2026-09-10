-- =====================================================
-- VELTRO - Inicialización del Master
-- =====================================================

-- Base de datos de la aplicación Laravel
CREATE DATABASE IF NOT EXISTS veltro_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- =====================================================
-- USUARIOS DE SISTEMA
-- =====================================================

-- Acceso de la aplicación Laravel
GRANT ALL PRIVILEGES ON veltro_local.* TO 'veltro_app'@'%';

-- Usuario replicator (para replicación)
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'Replicator_V3ltr0_2025!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';

-- Usuario exporter (para Prometheus)
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED WITH mysql_native_password BY 'Exp0rt3r_2025!';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

-- Crear usuario backup
CREATE USER IF NOT EXISTS 'backup_user'@'%' IDENTIFIED WITH mysql_native_password BY 'B4ckup_V3ltr0_2025!';
GRANT SELECT, LOCK TABLES, SHOW VIEW, PROCESS, RELOAD, REPLICATION CLIENT ON *.* TO 'backup_user'@'%';

-- Usuario haproxy_check (healthcheck de HAProxy - "option mysql-check")
-- No necesita privilegios ni contraseña: HAProxy solo lee el paquete de
-- handshake inicial para saber si el servidor responde, nunca completa el login.
CREATE USER IF NOT EXISTS 'haproxy_check'@'%';

FLUSH PRIVILEGES;
