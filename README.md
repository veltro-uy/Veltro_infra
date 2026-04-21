# 🚀 VELTRO ENTERPRISE - INFRAESTRUCTURA DOCKER

![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)
![Status](https://img.shields.io/badge/Status-Production-green)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)
![License](https://img.shields.io/badge/License-Private-red)
![Version](https://img.shields.io/badge/Version-1.0.0-orange)

---

## 📑 Índice

- [📋 Requisitos Previos](#-requisitos-previos)
- [🚀 Instalación](#-instalación-y-puesta-en-marcha)
- [🔧 Servicios y Puertos](#-servicios-y-puertos)
- [📊 Comandos Útiles](#-comandos-útiles)
- [🔄 Reinicio Completo](#-reinicio-completo-desde-cero)
- [🐛 Solución de Problemas](#-solución-de-problemas-comunes)
- [📁 Estructura de Archivos](#-estructura-de-archivos)
- [🔐 Credenciales](#-credenciales)

---

## 📋 REQUISITOS PREVIOS

> ⚠️ Asegurate de cumplir con estos requisitos antes de comenzar

- **Docker Desktop** 4.0+ (Windows 10/11 Pro/Enterprise)
- **PowerShell** 5.1+ (recomendado) o CMD
- **Git** (opcional)

### 💻 Recursos mínimos

| Recurso | Requerimiento |
|---------|--------------|
| RAM     | 8 GB mínimo (16 GB recomendado) |
| Disco   | 20 GB libres |
| CPU     | 4 núcleos |

---

## 🚀 INSTALACIÓN Y PUESTA EN MARCHA

### 1. Clonar/Descargar el proyecto

```powershell
git clone <url-del-repositorio> Veltro_infra
cd Veltro_infra
```

### 2. Crear carpetas necesarias

```powershell
New-Item -ItemType Directory -Force -Path @(
    "data/db-master","data/db-slave","data/web","data/grafana",
    "data/prometheus","data/backup","data/fileserver",
    "logs/web","logs/db-master","logs/db-slave","logs/haproxy",
    "logs/backup","logs/waf","logs/monitoring"
) | Out-Null
```

### 3. Levantar toda la infraestructura

```powershell
docker-compose up -d
docker-compose logs -f
```

### 4. Esperar la inicialización

⏱️ La primera vez puede tomar 2-3 minutos.

```powershell
Start-Sleep -Seconds 90
```

### 5. Verificar funcionamiento

```powershell
docker-compose ps

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SHOW SLAVE STATUS\G" | Select-String "Running"

docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "SELECT COUNT(*) FROM veltro_prod.equipos;"
```

---

## 🔧 SERVICIOS Y PUERTOS

| Servicio | Contenedor | Puerto | Acceso |
|----------|-----------|--------|--------|
| Web App | svveltroweb | 8081 | http://localhost:8081 |
| WAF | veltrowaf | 8088 | http://localhost:8088 |
| MySQL Master | svveltrobdm | 3316 | root / MasterDB_V3ltr0_2025! |
| MySQL Slave | svveltrobds | 3307 | root / SlaveDB_V3ltr0_2025! |
| HAProxy Write | sqlproxy | 6033 | - |
| HAProxy Read | sqlproxy | 6032 | - |
| HAProxy Stats | sqlproxy | 8404 | admin / admin |
| Prometheus | svveltromonit | 9090 | http://localhost:9090 |
| Grafana | grafana | 3000 | admin / Gr4f4n4_V3ltr0_2025! |
| Backup SSH | svveltrobackup | 2022 | root / B4ckupR00t_V3ltr0_2025! |
| File Server | fileserver | 2222 | mlopez / Admin_V3ltr0_2025! |
| Exporter Master | mysql-exporter-master | 9104 | - |
| Exporter Slave | mysql-exporter-slave | 9105 | - |

---

## 📊 COMANDOS ÚTILES

### 🧩 Gestión

```powershell
docker-compose ps
docker-compose logs svveltrobdm --tail 50
docker-compose restart svveltrobds
docker-compose stop
docker-compose start
docker-compose down
```

### 🗄️ Base de datos

```powershell
docker exec -it svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025!
docker exec -it svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025!
```

### 🔑 SSH

```powershell
ssh -p 2022 root@localhost
ssh -p 2222 mlopez@localhost
```

### 📈 Monitoreo

```powershell
curl http://localhost:9090/api/v1/targets
curl http://localhost:8404/stats
```

---

## 🔄 REINICIO COMPLETO (DESDE CERO)

```powershell
docker-compose down -v

Remove-Item -Path ".\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\logs" -Recurse -Force -ErrorAction SilentlyContinue

docker-compose build --no-cache
docker-compose up -d

Start-Sleep -Seconds 90

docker-compose ps
```

---

## 🐛 SOLUCIÓN DE PROBLEMAS COMUNES

### Error: contenedor unhealthy

```powershell
docker logs svveltrobds --tail 50
docker-compose restart svveltrobds
```

### Error: Access denied

```powershell
docker-compose rm -f svveltrobds
Remove-Item -Path ".\data\db-slave" -Recurse -Force
docker-compose up -d svveltrobds
```

### Error: Slave_SQL_Running: No

```powershell
docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "STOP SLAVE; START SLAVE;"
```

---

## 📁 ESTRUCTURA DE ARCHIVOS

```text
Veltro_infra/
├── docker-compose.yml
├── .env
├── config/
├── scripts/
├── build/
├── data/
└── logs/
```

---

## 🔐 CREDENCIALES

| Servicio | Usuario | Contraseña |
|----------|--------|------------|
| MySQL Master | root | MasterDB_V3ltr0_2025! |
| MySQL Slave | root | SlaveDB_V3ltr0_2025! |
| Grafana | admin | Gr4f4n4_V3ltr0_2025! |
| Backup SSH | root | B4ckupR00t_V3ltr0_2025! |
| File Server | mlopez | Admin_V3ltr0_2025! |
| File Server | fmartinez | Dev_V3ltr0_2025! |
| File Server | ngalego | Dev_V3ltr0_2025! |
| File Server | mlandaco | Dev_V3ltr0_2025! |
| File Server | pfumero | Test_V3ltr0_2025! |

---

## 📌 NOTAS FINALES

- Esperar ~90 segundos tras iniciar
- Verificar con `docker-compose ps`
- Revisar logs ante fallos
- La replicación se configura automáticamente

---

## 🏁 VELTRO ENTERPRISE

Infraestructura robusta, escalable y lista para producción 🚀
