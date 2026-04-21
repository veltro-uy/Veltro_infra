# 🚀 VELTRO ENTERPRISE

### Infraestructura Docker de Alto Rendimiento

<p align="left">
  <img src="https://img.shields.io/badge/Docker-Ready-blue?logo=docker" />
  <img src="https://img.shields.io/badge/Status-Production-green" />
  <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11-blue" />
  <img src="https://img.shields.io/badge/License-Private-red" />
  <img src="https://img.shields.io/badge/Version-1.0.0-orange" />
</p>

---

## 📑 Índice

* [📋 Requisitos Previos](#-requisitos-previos)
* [🚀 Instalación y Puesta en Marcha](#-instalación-y-puesta-en-marcha)
* [🔧 Servicios y Puertos](#-servicios-y-puertos)
* [📊 Comandos Útiles](#-comandos-útiles)
* [🔄 Reinicio Completo](#-reinicio-completo-desde-cero)
* [🐛 Solución de Problemas Comunes](#-solución-de-problemas-comunes)

  * [🔑 Problema de known_hosts (claves SSH)](#-problema-de-known_hosts-claves-ssh)
* [📁 Estructura de Archivos](#-estructura-de-archivos)
* [🔐 Credenciales](#-credenciales)
* [📌 Notas Finales](#-notas-finales)

---

## 📋 Requisitos Previos

> ⚠️ Asegurate de cumplir con estos requisitos antes de comenzar

| Requisito          | Versión / Especificación            |
| ------------------ | ----------------------------------- |
| **Docker Desktop** | 4.0+ (Windows 10/11 Pro/Enterprise) |
| **PowerShell**     | 5.1+ (recomendado) o CMD            |
| **Git**            | Opcional                            |
| **RAM**            | 8 GB mínimo (16 GB recomendado)     |
| **Disco**          | 20 GB libres                        |
| **CPU**            | 4 núcleos                           |

---

## 🚀 Instalación y Puesta en Marcha

### 1. Clonar/Descargar el proyecto

```powershell
git clone <url-del-repositorio> Veltro_infra
cd Veltro_infra
```

### 2. Crear carpetas necesarias

```powershell
# Desde PowerShell (como Administrador)
New-Item -ItemType Directory -Force -Path @(
    "data/db-master","data/db-slave","data/web","data/grafana",
    "data/prometheus","data/backup","data/fileserver",
    "logs/web","logs/db-master","logs/db-slave","logs/haproxy",
    "logs/backup","logs/waf","logs/monitoring"
) | Out-Null
```

### 3. Configurar archivo `.env` (opcional)

El archivo `.env` ya contiene configuraciones por defecto. Si querés modificarlas:

```env
# Contraseñas (cambiar si se desea)
DB_ROOT_PASSWORD=MasterDB_V3ltr0_2025!
DB_SLAVE_ROOT_PASSWORD=SlaveDB_V3ltr0_2025!
DB_APP_PASSWORD=V3ltr0App_2025!
DB_REPLICATION_PASSWORD=Replicator_V3ltr0_2025!
GRAFANA_ADMIN_PASSWORD=Gr4f4n4_V3ltr0_2025!

# Puertos (opcional)
WEB_HTTP_PORT=8081
DB_MASTER_PORT=3316
DB_SLAVE_PORT=3307
```

### 4. Levantar toda la infraestructura

```powershell
# Iniciar todos los servicios
docker-compose up -d

# Ver logs (opcional)
docker-compose logs -f
```

### 5. Esperar la inicialización

⏱️ La primera vez puede tomar 2-3 minutos.

```powershell
Start-Sleep -Seconds 90
```

### 6. Verificar funcionamiento

```powershell
docker-compose ps

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | Select-String "Running"

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SELECT COUNT(*) FROM veltro_prod.equipos;"
```

---

## 🔧 Servicios y Puertos

| Servicio              | Contenedor            | Puerto | Acceso / Credenciales          |
| --------------------- | --------------------- | ------ | ------------------------------ |
| Web App               | svveltroweb           | 8081   | http://localhost:8081          |
| WAF                   | veltrowaf             | 8088   | http://localhost:8088          |
| MySQL Master          | svveltrobdm           | 3316   | root / MasterDB_V3ltr0_2025!   |
| MySQL Slave           | svveltrobds           | 3307   | root / SlaveDB_V3ltr0_2025!    |
| HAProxy (Escritura)   | sqlproxy              | 6033   | Balanceo                       |
| HAProxy (Lectura)     | sqlproxy              | 6032   | Balanceo                       |
| HAProxy Stats         | sqlproxy              | 8404   | admin / admin                  |
| Prometheus            | svveltromonit         | 9090   | http://localhost:9090          |
| Grafana               | grafana               | 3000   | admin / Gr4f4n4_V3ltr0_2025!   |
| Backup Server SSH     | svveltrobackup        | 2022   | root / B4ckupR00t_V3ltr0_2025! |
| File Server SSH       | fileserver            | 2222   | mlopez / Admin_V3ltr0_2025!    |
| MySQL Exporter Master | mysql-exporter-master | 9104   | Métricas                       |
| MySQL Exporter Slave  | mysql-exporter-slave  | 9105   | Métricas                       |

---

## 📊 Comandos Útiles

### 🧩 Gestión de contenedores

```powershell
docker-compose ps
docker-compose logs svveltrobdm --tail 50
docker-compose restart svveltrobds
docker-compose stop
docker-compose start
docker-compose down
```

### 🗄️ Acceso a bases de datos

```powershell
docker exec -it svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025!
docker exec -it svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025!
```

### 🔑 Acceso SSH

```powershell
ssh -p 2022 root@localhost
ssh -p 2222 mlopez@localhost
```

### 📈 Monitoreo

```powershell
curl http://localhost:9090/api/v1/targets
curl http://localhost:8404/stats
```

### 🔁 Prueba de replicación

```powershell
docker exec svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025! -e "
CREATE DATABASE test_replica;
USE test_replica;
CREATE TABLE prueba (id INT, nombre VARCHAR(50));
INSERT INTO prueba VALUES (1, 'Test replicación');
"

Start-Sleep -Seconds 2

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "USE test_replica; SELECT * FROM prueba;"
```

---

## 🔄 Reinicio Completo (desde cero)

⚠️ Este proceso elimina todos los datos.

```powershell
cd C:\ruta\Veltro_infra

# 1. Detener y eliminar todo
docker-compose down -v

# 2. Eliminar datos
Remove-Item -Path ".\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\logs" -Recurse -Force -ErrorAction SilentlyContinue

# 3. Recrear carpetas
New-Item -ItemType Directory -Force -Path @(
    "data/db-master","data/db-slave","data/web","data/grafana",
    "data/prometheus","data/backup","data/fileserver"
) | Out-Null

# 4. Reconstruir imágenes (opcional)
docker-compose build --no-cache

# 5. Levantar todo
docker-compose up -d

# 6. Esperar inicialización
Start-Sleep -Seconds 90

# 7. Verificar
docker-compose ps
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | Select-String "Running"
```

---

## 🐛 Solución de Problemas Comunes

### 🔸 Error: container svveltrobds is unhealthy

```powershell
docker logs svveltrobds --tail 50
docker-compose restart svveltrobds
```

### 🔸 Error: Access denied for user

```powershell
docker-compose stop svveltrobds
docker-compose rm -f svveltrobds
```

### 🔸 Error: Slave_SQL_Running: No

```powershell
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "STOP SLAVE; START SLAVE;"
```

### 🔸 Error: Puertos en uso

```powershell
docker-compose down
docker-compose up -d
```

---

## 🔑 Problema de known_hosts (claves SSH)

```powershell
ssh-keygen -R "[localhost]:2022"
ssh-keygen -R "[localhost]:2222"
```

---

## 📁 Estructura de Archivos

```text
Veltro_infra/
├── docker-compose.yml
├── .env
├── README.md
├── config/
│   ├── db-master/
│   │   ├── master.cnf
│   │   └── init-master.sql
│   ├── apache/
│   │   └── veltro.conf
│   ├── haproxy/
│   │   └── haproxy.cfg
│   ├── prometheus/
│   │   └── prometheus.yml
│   └── waf/
│       └── default.conf.template
├── scripts/
│   ├── backup/
│   │   ├── setup_backup_server.sh
│   │   ├── backup_full_monthly.sh
│   │   ├── backup_incremental_weekly.sh
│   │   ├── cleanup_old_backups.sh
│   │   └── check_backup_integrity.sh
│   └── init/
│       ├── setup_fileserver.sh
│       └── setup_replication_on_slave.sh
├── build/
│   └── web/
│       └── Dockerfile
├── data/          (se crea automáticamente)
└── logs/          (se crea automáticamente)
```

---

## 🔐 Credenciales

| Servicio            | Usuario    | Contraseña              |
| ------------------- | ---------- | ----------------------- |
| MySQL Master        | root       | MasterDB_V3ltr0_2025!   |
| MySQL Slave         | root       | SlaveDB_V3ltr0_2025!    |
| Usuario replicación | replicator | Replicator_V3ltr0_2025! |
| Usuario exporter    | exporter   | Exp0rt3r_2025!          |
| Grafana             | admin      | Gr4f4n4_V3ltr0_2025!    |
| Backup Server SSH   | root       | B4ckupR00t_V3ltr0_2025! |
| File Server SSH     | mlopez     | Admin_V3ltr0_2025!      |
| File Server SSH     | fmartinez  | Dev_V3ltr0_2025!        |
| File Server SSH     | ngalego    | Dev_V3ltr0_2025!        |
| File Server SSH     | mlandaco   | Dev_V3ltr0_2025!        |
| File Server SSH     | pfumero    | Test_V3ltr0_2025!       |
| HAProxy Stats       | admin      | admin                   |

---

## 📌 Notas Finales

* ✅ Esperar ~90 segundos tras levantar los servicios
* ✅ Verificar con `docker-compose ps` que estén **Up/Healthy**
* ✅ Revisar logs ante fallos: `docker-compose logs --tail 100 <servicio>`
* ✅ La replicación se configura automáticamente
* ✅ Datos de prueba cargados en el Master
* ✅ Backup Server accede al File Server vía SSH sin contraseña
* ✅ Si aparece error de SSH, ver sección *known_hosts*

---

## 🏁 VELTRO ENTERPRISE

**Infraestructura robusta, escalable y lista para producción 🚀**
