# 🚀 VELTRO ENTERPRISE

### Infraestructura Docker de Alto Rendimiento

<p align="left">
  <img src="https://img.shields.io/badge/Docker-Ready-blue?logo=docker" />
  <img src="https://img.shields.io/badge/Status-Production-green" />
  <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11%20%7C%20Linux-blue" />
  <img src="https://img.shields.io/badge/License-Private-red" />
  <img src="https://img.shields.io/badge/Version-2.0.0-orange" />
</p>

---

## 📑 ÍNDICE

- [📋 Requisitos Previos](#-requisitos-previos)
- [🚀 Instalación Completa (desde cero)](#-instalación-completa-desde-cero)
- [🔧 Servicios y Puertos](#-servicios-y-puertos)
- [⚙️ Comandos Útiles](#️-comandos-útiles)
- [✅ Verificación de la Infraestructura](#-verificación-de-la-infraestructura)
- [🔄 Reinicio Completo (borrando datos)](#-reinicio-completo-borrando-datos)
- [🐛 Solución de Problemas Comunes](#-solución-de-problemas-comunes)
- [📁 Estructura de Archivos](#-estructura-de-archivos)
- [🔐 Credenciales](#-credenciales)
- [📌 Notas Finales](#-notas-finales)

---

## 📋 REQUISITOS PREVIOS

> ⚠️ Asegurate de cumplir con estos requisitos antes de comenzar

| Requisito | Windows | Linux/WSL |
|-----------|---------|-----------|
| **Docker** | Docker Desktop 4.0+ | Docker Engine 20.10+ |
| **Shell** | PowerShell 5.1+ | Bash 4.0+ |
| **Git** | Opcional | Opcional |
| **RAM** | 8 GB mínimo (16 GB recomendado) |
| **Disco** | 20 GB libres |
| **CPU** | 4 núcleos |

---

## 🚀 Instalación Completa (desde cero)

Estos pasos son los necesarios **siempre** que se levanta el proyecto por primera vez, o después de un `docker-compose down -v`. Son obligatorios, no opcionales — sin los pasos 5 y 6 la infraestructura queda levantada pero incompleta (sin acceso SSH entre Backup Server y File Server, y sin dashboards en Grafana).

### 1. Clonar el proyecto

```bash
git clone <url-del-repositorio> Veltro_infra
cd Veltro_infra
```

### 2. Crear carpetas necesarias

**PowerShell:**
```powershell
New-Item -ItemType Directory -Force -Path @(
    "data/db-master","data/db-slave","data/web","data/grafana",
    "data/prometheus","data/backup","data/fileserver",
    "logs/web","logs/db-master","logs/db-slave","logs/haproxy",
    "logs/backup","logs/waf","logs/monitoring"
) | Out-Null
```

**Bash:**
```bash
mkdir -p data/{db-master,db-slave,web,grafana,prometheus,backup,fileserver}
mkdir -p logs/{web,db-master,db-slave,haproxy,backup,waf,monitoring}
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
WEB_HTTP_PORT=8181
DB_MASTER_PORT=3316
DB_SLAVE_PORT=3307
```

### 4. Levantar toda la infraestructura

```bash
docker-compose up -d

# Ver logs (opcional)
docker-compose logs -f
```

⏱️ La primera vez puede tomar 2-3 minutos (instalación de paquetes dentro de los contenedores Fedora). Esperá antes de continuar:

```powershell
Start-Sleep -Seconds 120
```
```bash
sleep 120
```

### 5. Configurar SSH (OBLIGATORIO)

Instala automáticamente la clave SSH del Backup Server en el File Server. Sin este paso, los backups automáticos del Fileserver van a fallar.

```bash
./scripts/init/setup-ssh-config.sh
```

### 6. Crear Dashboards de Grafana (OBLIGATORIO)

```bash
docker cp scripts/init/grafana-dashboards.sh grafana:/tmp/
docker exec grafana chmod +x /tmp/grafana-dashboards.sh
docker exec grafana bash /tmp/grafana-dashboards.sh
```

### 7. Verificar que todo esté sano

```bash
docker-compose ps
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | grep "Running"
./scripts/init/verify-backup-chain.sh
```

`docker-compose ps` debe mostrar todos los contenedores `Up` (o `Healthy` los que tienen healthcheck). `Slave_IO_Running` y `Slave_SQL_Running` deben decir `Yes`. `verify-backup-chain.sh` debe terminar con `0 FALLOS`.

Ver [Verificación de la Infraestructura](#-verificación-de-la-infraestructura) para chequeos más profundos, y [Servicios y Puertos](#-servicios-y-puertos) para saber qué URL/credencial usar en cada caso.

---

## 🔧 Servicios y Puertos

| Servicio              | Contenedor            | Puerto | Acceso / Credenciales          |
| --------------------- | --------------------- | ------ | ------------------------------ |
| Web App               | svveltroweb           | 8181   | http://localhost:8181          |
| WAF                   | veltrowaf             | 8188   | http://localhost:8188          |
| MySQL Master          | svveltrobdm           | 3316   | root / MasterDB_V3ltr0_2025!   |
| MySQL Slave           | svveltrobds           | 3307   | root / SlaveDB_V3ltr0_2025!    |
| HAProxy (Escritura)   | sqlproxy              | 6033   | Balanceo                       |
| HAProxy (Lectura)     | sqlproxy              | 6032   | Balanceo                       |
| HAProxy Stats         | sqlproxy              | 8404   | http://localhost:8404/stats (admin/admin) |
| Prometheus            | svveltromonit         | 9090   | http://localhost:9090          |
| Grafana               | grafana               | 3000   | http://localhost:3000 (admin / Gr4f4n4_V3ltr0_2025!) |
| Backup Server SSH     | svveltrobackup        | 2022   | backup / Clave SSH             |
| File Server SSH       | fileserver            | 2322   | mlopez, fmartinez, ngalego, mlandaco, pfumero / Clave SSH |
| MySQL Exporter Master | mysql-exporter-master | 9104   | Métricas                       |
| MySQL Exporter Slave  | mysql-exporter-slave  | 9105   | Métricas                       |

---

## ⚙️ Comandos Útiles

### 🧩 Gestión de contenedores

```bash
docker-compose ps
docker-compose logs svveltrobdm --tail 50
docker-compose restart svveltrobds
docker-compose stop
docker-compose start
docker-compose down
```

### 🗄️ Acceso a bases de datos

```bash
docker exec -it svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025!
docker exec -it svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025!
```

### 🔁 Prueba de replicación

```bash
docker exec svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025! -e "
CREATE DATABASE IF NOT EXISTS test_replica;
USE test_replica;
CREATE TABLE IF NOT EXISTS prueba (id INT, nombre VARCHAR(50));
INSERT INTO prueba VALUES (1, 'Test replicación');
"

sleep 2   # En PowerShell: Start-Sleep -Seconds 2

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "USE test_replica; SELECT * FROM prueba;"
```

### 📈 Monitoreo

```bash
curl http://localhost:9090/api/v1/targets
curl http://localhost:8404/stats
```

### 🔐 Acceso a servidores vía SSH

```bash
# Backup Server
ssh backup

# File Server
ssh mlopez
ssh fmartinez
ssh ngalego
ssh mlandaco
ssh pfumero
```

### 💾 Backups manuales

```bash
# Backup completo mensual
docker exec -u backup svveltrobackup bash /scripts/backup_full_monthly.sh

# Backup incremental semanal
docker exec -u backup svveltrobackup bash /scripts/backup_incremental_weekly.sh

# Verificar integridad de los backups existentes
docker exec -u backup svveltrobackup bash /scripts/check_backup_integrity.sh

# Limpieza de backups antiguos
docker exec -u backup svveltrobackup bash /scripts/cleanup_old_backups.sh
```

### 🧱 Prueba del WAF

El WAF corta la conexión (no responde con un código HTTP) ante un ataque detectado, así que un simple `curl` sin verbose puede devolver `000` incluso cuando el bloqueo funcionó correctamente. Para probarlo bien, usar el payload codificado y `-v`:

```bash
curl -sv -o /dev/null -w "HTTP: %{http_code}\n" "http://localhost:8188/?id=1%27%20OR%20%271%27%3D%271" 2>&1 | tail -20
```

Si la conexión se resetea (`curl: (56) Recv failure` o similar) o devuelve `403`, el WAF está bloqueando correctamente. Para más detalle, ver el audit log de ModSecurity:

```bash
docker exec veltrowaf find / -iname "*modsec_audit*" 2>/dev/null
```

---

## ✅ Verificación de la Infraestructura

Además de los chequeos rápidos del paso 7 de instalación, hay un script dedicado a validar de punta a punta la cadena de backups (clave SSH, `known_hosts`, conectividad real, acceso a MySQL, y una transferencia de prueba sin escribir nada en disco):

```bash
./scripts/init/verify-backup-chain.sh
```

Es **manual y opcional** — no se ejecuta automáticamente al levantar Docker. Se recomienda correrlo después de cualquier `docker-compose down && up`, o cuando algo en los backups no se vea bien. Termina con código de salida `0` si todo está sano, o `1` si encontró algún problema (y te dice cuál).

Para otros chequeos manuales de la infraestructura (replicación, HAProxy, WAF, Prometheus), ver los comandos en la sección anterior.

---

## 🔄 Reinicio Completo (borrando datos)

⚠️ Este proceso elimina **todos los datos** (bases de datos, backups, archivos del fileserver).

**PowerShell:**
```powershell
cd C:\ruta\Veltro_infra
docker-compose down -v
Remove-Item -Path ".\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\logs" -Recurse -Force -ErrorAction SilentlyContinue
```

**Bash:**
```bash
cd /ruta/Veltro_infra
docker-compose down -v
rm -rf data/ logs/
```

Después de esto, repetí los pasos **2 a 7** de [Instalación Completa](#-instalación-completa-desde-cero) (recrear carpetas, levantar contenedores, configurar SSH, dashboards, y verificar).

---

## 🐛 Solución de Problemas Comunes

### 🔸 Error: container svveltrobds is unhealthy

```bash
docker logs svveltrobds --tail 50
docker-compose restart svveltrobds
```

### 🔸 Error: Access denied for user

```bash
docker-compose stop svveltrobds
docker-compose rm -f svveltrobds
docker-compose up -d svveltrobds
```

### 🔸 Error: Slave_SQL_Running: No

```bash
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "STOP SLAVE; START SLAVE;"
```

### 🔸 Error: Puertos en uso

```bash
docker-compose down
docker-compose up -d
```

### 🔸 Problema de known_hosts / conexión SSH rechazada

Puede pasar después de un `docker-compose down -v` (contenedores nuevos = clave nueva), o si se corrió `setup-ssh-config.sh` antes de que los contenedores terminaran de inicializar.

```bash
chmod +x scripts/init/setup-ssh-config.sh
./scripts/init/setup-ssh-config.sh

# Si el error persiste, limpiar known_hosts del host y reintentar
ssh-keygen -R "[localhost]:2022"
ssh-keygen -R "[localhost]:2322"
./scripts/init/setup-ssh-config.sh
```

### 🔸 Los backups automáticos no corren / fallan en silencio

```bash
./scripts/init/verify-backup-chain.sh
```

Te va a decir exactamente en qué punto de la cadena está el problema (clave no generada, clave no instalada, SSH sin conexión, MySQL sin acceso, o transferencia fallida). El caso más común es que se haya hecho un `docker-compose down` + `up` (recreate) sin volver a correr `setup-ssh-config.sh` después.

### 🔸 Las métricas de backup no aparecen en Grafana

```bash
docker exec svveltrobackup /usr/local/bin/backup_metrics.sh
docker exec svveltrobackup cat /var/lib/node_exporter/textfile/backup.prom
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
│   │   ├── backup_fileserver.sh
│   │   ├── backup_incremental_weekly.sh
│   │   ├── cleanup_old_backups.sh
│   │   └── check_backup_integrity.sh
│   └── init/
│       ├── setup_fileserver.sh
│       ├── setup_replication_on_slave.sh
│       ├── setup-ssh-config.sh
│       ├── verify-backup-chain.sh
│       └── grafana-dashboards.sh
├── build/
│   └── web/
│       └── Dockerfile
├── data/          (se crea automáticamente)
└── logs/          (se crea automáticamente)
```

---

## 🔐 Credenciales

| Servicio            | Usuario    | Contraseña               |
| -------------------- | ---------- | ------------------------ |
| MySQL Master         | root       | MasterDB_V3ltr0_2025!    |
| MySQL Slave          | root       | SlaveDB_V3ltr0_2025!     |
| Usuario replicación  | replicator | Replicator_V3ltr0_2025!  |
| Usuario exporter     | exporter   | Exp0rt3r_2025!           |
| Grafana              | admin      | Gr4f4n4_V3ltr0_2025!     |
| Backup Server (user) | backup     | B4ckup_V3ltr0_2025!      |
| File Server          | mlopez     | Admin_V3ltr0_2025!       |
| File Server          | fmartinez  | Dev_V3ltr0_2025!         |
| File Server          | ngalego    | Dev_V3ltr0_2025!         |
| File Server          | mlandaco   | Dev_V3ltr0_2025!         |
| File Server          | pfumero    | Test_V3ltr0_2025!        |
| HAProxy Stats        | admin      | admin                    |

> ℹ️ El acceso SSH real entre Backup Server y File Server es **por clave pública**, no por contraseña (`PasswordAuthentication no`). Las contraseñas de la tabla son las de los usuarios del sistema operativo dentro de cada contenedor, no credenciales de login SSH.

---

## 📌 Notas Finales

* ✅ Esperar ~120 segundos tras levantar los servicios antes de correr los pasos post-instalación
* ✅ Correr `setup-ssh-config.sh` y el script de dashboards son pasos **obligatorios**, no opcionales
* ✅ Verificar con `docker-compose ps` que todos los contenedores estén `Up`/`Healthy`
* ✅ Correr `./scripts/init/verify-backup-chain.sh` después de cualquier recreate de contenedores
* ✅ Revisar logs ante fallos: `docker-compose logs --tail 100 <servicio>`
* ✅ La replicación MySQL se configura automáticamente
* ✅ El Backup Server accede al File Server vía SSH sin contraseña (por clave)
* ✅ Ante error de SSH o `known_hosts`, ver la sección de [Solución de Problemas](#-solución-de-problemas-comunes)
* ⚠️ Esperar a que todos los contenedores estén `Healthy` antes de dar por buena la instalación

---

## 🏁 VELTRO ENTERPRISE

**Infraestructura robusta, escalable y lista para producción 🚀**