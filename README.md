# 🚀 VELTRO ENTERPRISE - INFRAESTRUCTURA DOCKER

![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)
![Status](https://img.shields.io/badge/Status-Production-green)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)
![License](https://img.shields.io/badge/License-Private-red)
![Version](https://img.shields.io/badge/Version-1.0.0-orange)

---

## 📑 Índice

* [📋 Requisitos Previos](#-requisitos-previos)
* [🚀 Instalación](#-instalación-y-puesta-en-marcha)

  * [1. Clonar proyecto](#1-clonardescargar-el-proyecto)
  * [2. Estructura](#2-verificar-estructura-de-archivos)
  * [3. Levantar servicios](#3-levantar-toda-la-infraestructura)
  * [4. Verificación](#4-verificar-que-todo-funciona)
* [🔧 Servicios y Puertos](#-servicios-y-puertos)
* [📊 Comandos Útiles](#-comandos-útiles)
* [🔄 Reinicio Completo](#-reinicio-completo-desde-cero)
* [🐛 Solución de Problemas](#-solución-de-problemas-comunes)

---

## 📋 REQUISITOS PREVIOS

> ⚠️ Asegurate de cumplir con estos requisitos antes de comenzar

* **Docker Desktop** 4.0+ (Windows 10/11 Pro/Enterprise)
* **PowerShell** 5.1+ (recomendado) o CMD
* **Git** (opcional)

### 💻 Recursos mínimos

| Recurso | Requerimiento |
| ------- | ------------- |
| RAM     | 8 GB          |
| Disco   | 20 GB         |
| CPU     | 4 núcleos     |

---

## 🚀 INSTALACIÓN Y PUESTA EN MARCHA

### 1. Clonar/Descargar el proyecto

```powershell
git clone <url-del-repositorio> Veltro_infra
cd Veltro_infra
```

---

### 2. Verificar estructura de archivos

```bash
Veltro_infra/
├── docker-compose.yml
├── .env
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
│   └── init/
│       └── setup_replication_on_slave.sh
├── build/
│   └── web/
│       └── Dockerfile
├── data/          (se crea automáticamente)
└── logs/          (se crea automáticamente)
```

---

### 3. Levantar toda la infraestructura

```powershell
# Desde PowerShell (como Administrador)
cd C:\ruta\Veltro_infra

# Crear carpetas necesarias
New-Item -ItemType Directory -Force -Path `
"data/db-master","data/db-slave","data/web","data/grafana","data/prometheus","data/backup","data/fileserver" | Out-Null

New-Item -ItemType Directory -Force -Path `
"logs/web","logs/db-master","logs/db-slave","logs/haproxy","logs/backup","logs/waf","logs/monitoring" | Out-Null

# Iniciar todos los servicios
docker-compose up -d
```

---

### 4. Verificar que todo funciona

```powershell
# Estado de los contenedores
docker-compose ps

# Verificar replicación MySQL
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | Select-String "Running"

# Verificar datos en Slave
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SELECT COUNT(*) FROM veltro_prod.equipos;"
```

---

## 🔧 SERVICIOS Y PUERTOS

| Servicio              | Contenedor            | Puerto      | Acceso / Credenciales        |
| --------------------- | --------------------- | ----------- | ---------------------------- |
| Web App               | svveltroweb           | 8081        | http://localhost:8081        |
| WAF                   | veltrowaf             | 8088        | http://localhost:8088        |
| MySQL Master          | svveltrobdm           | 3316        | root / MasterDB_V3ltr0_2025! |
| MySQL Slave           | svveltrobds           | 3307        | root / SlaveDB_V3ltr0_2025!  |
| HAProxy (Write/Read)  | sqlproxy              | 6033 / 6032 | -                            |
| HAProxy Stats         | sqlproxy              | 8404        | admin / admin                |
| Prometheus            | svveltromonit         | 9090        | http://localhost:9090        |
| Grafana               | grafana               | 3000        | admin / Gr4f4n4_V3ltr0_2025! |
| Backup Server (SSH)   | svveltrobackup        | 2022        | root                         |
| File Server (SSH)     | fileserver            | 2222        | mlopez                       |
| MySQL Exporter Master | mysql-exporter-master | 9104        | -                            |
| MySQL Exporter Slave  | mysql-exporter-slave  | 9105        | -                            |

---

## 📊 COMANDOS ÚTILES

### 🧩 Gestión de contenedores

```powershell
docker-compose ps
docker-compose logs svveltrobdm
docker-compose logs svveltrobds --tail 50
docker-compose restart svveltrobds
docker-compose stop
docker-compose start
docker-compose down
```

---

### 📈 Monitoreo

```powershell
curl http://localhost:9090/api/v1/targets
curl http://localhost:8404/stats
curl http://localhost:9104/metrics | findstr "mysql_up"
curl http://localhost:9105/metrics | findstr "mysql_up"
```

---

### 🔁 Prueba de replicación

```powershell
# Crear datos en Master
docker exec svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025! -e "
CREATE DATABASE test_replica;
USE test_replica;
CREATE TABLE prueba (id INT, nombre VARCHAR(50));
INSERT INTO prueba VALUES (1, 'Test replicación');
"

# Verificar en Slave
Start-Sleep -Seconds 2
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "USE test_replica; SELECT * FROM prueba;"

# Limpiar
docker exec svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025! -e "DROP DATABASE test_replica;"
```

---

## 🔄 REINICIO COMPLETO (DESDE CERO)

```powershell
cd C:\ruta\Veltro_infra

docker-compose down -v

Remove-Item -Path ".\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\logs" -Recurse -Force -ErrorAction SilentlyContinue

docker-compose build --no-cache
docker-compose up -d

Start-Sleep -Seconds 90

docker-compose ps
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | Select-String "Running"
```

---

## 🐛 SOLUCIÓN DE PROBLEMAS COMUNES

### 🔸 Ver logs del Slave

```powershell
docker logs svveltrobds --tail 50
```

---

### 🔸 Error: Access denied for user 'root'@'localhost'

```powershell
docker-compose stop svveltrobds
docker-compose rm -f svveltrobds
Remove-Item -Path ".\data\db-slave" -Recurse -Force
docker-compose up -d svveltrobds
```

---

### 🔸 Error: Slave_SQL_Running: No

```powershell
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "STOP SLAVE; START SLAVE;"
```

---

### 🔸 Error: Exporters no funcionan

```powershell
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED WITH mysql_native_password BY 'Exp0rt3r_2025!';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
"

docker-compose restart mysql-exporter-master mysql-exporter-slave
```

---

## 📌 NOTAS FINALES

* ✔️ Esperar ~90 segundos tras levantar los servicios
* ✔️ Verificar siempre con `docker-compose ps`
* ✔️ Revisar logs ante cualquier fallo

---

## 🏁 VELTRO ENTERPRISE

> Infraestructura robusta, escalable y lista para producción 🚀
