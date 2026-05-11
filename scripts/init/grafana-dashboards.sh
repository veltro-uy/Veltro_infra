#!/bin/bash
################################################################################
# VELTRO - Dashboards para Grafana
# Dashboards: MySQL, Sistema, Apache y Backups
################################################################################

echo "=== VELTRO - Configurando Dashboards ==="

# Esperar a que Grafana esté listo
until curl -s -f http://localhost:3000/api/health > /dev/null 2>&1; do
    echo "Esperando Grafana..."
    sleep 5
done

GRAFANA_USER="admin"
GRAFANA_PASS="Gr4f4n4_V3ltr0_2025!"

echo "✓ Grafana disponible"

# ==============================================
# DASHBOARD 1: MySQL
# ==============================================
echo ""
echo "[1/4] Creando Dashboard MySQL..."

curl -s -X POST "http://localhost:3000/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u $GRAFANA_USER:$GRAFANA_PASS \
    -d '{
  "dashboard": {
    "title": "VELTRO - MySQL",
    "tags": ["mysql", "veltro", "database"],
    "timezone": "browser",
    "schemaVersion": 36,
    "refresh": "30s",
    "panels": [
      {
        "title": "MySQL Master",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "mysql_up", "refId": "A"}],
        "fieldConfig": {
          "defaults": {
            "thresholds": {"steps": [{"color": "red"}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "value": "0", "text": "DOWN"}, {"type": "value", "value": "1", "text": "UP"}]
          }
        }
      },
      {
        "title": "MySQL Slave",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "mysql_up", "refId": "A"}],
        "fieldConfig": {
          "defaults": {
            "thresholds": {"steps": [{"color": "red"}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "value": "0", "text": "DOWN"}, {"type": "value", "value": "1", "text": "UP"}]
          }
        }
      },
      {
        "title": "Replication Lag",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [{"expr": "mysql_slave_status_seconds_behind_master", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "s"}}
      },
      {
        "title": "Queries per Second",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [{"expr": "rate(mysql_global_status_queries[5m])", "refId": "A"}]
      },
      {
        "title": "Connections",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
        "targets": [{"expr": "mysql_global_status_threads_connected", "refId": "A"}]
      },
      {
        "title": "Slow Queries",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
        "targets": [{"expr": "rate(mysql_global_status_slow_queries[5m])", "refId": "A"}]
      }
    ]
  },
  "overwrite": true
}' > /dev/null

echo "✓ Dashboard MySQL creado"

# ==============================================
# DASHBOARD 2: Sistema
# ==============================================
echo ""
echo "[2/4] Creando Dashboard Sistema..."

curl -s -X POST "http://localhost:3000/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u $GRAFANA_USER:$GRAFANA_PASS \
    -d '{
  "dashboard": {
    "title": "VELTRO - System",
    "tags": ["system", "veltro", "infrastructure"],
    "timezone": "browser",
    "schemaVersion": 36,
    "refresh": "30s",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [{"expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "percent"}}
      },
      {
        "title": "Memory Usage",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "targets": [{"expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "percent"}}
      },
      {
        "title": "Disk Usage",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [{"expr": "(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "percent"}}
      },
      {
        "title": "Network Traffic",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [
          {"expr": "rate(node_network_receive_bytes_total[5m])", "refId": "A"},
          {"expr": "rate(node_network_transmit_bytes_total[5m])", "refId": "B"}
        ],
        "fieldConfig": {"defaults": {"unit": "bps"}}
      },
      {
        "title": "System Load",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
        "targets": [{"expr": "node_load1", "refId": "A"}]
      },
      {
        "title": "Disk I/O",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
        "targets": [
          {"expr": "rate(node_disk_read_bytes_total[5m])", "refId": "A"},
          {"expr": "rate(node_disk_written_bytes_total[5m])", "refId": "B"}
        ],
        "fieldConfig": {"defaults": {"unit": "Bps"}}
      }
    ]
  },
  "overwrite": true
}' > /dev/null

echo "✓ Dashboard Sistema creado"

# ==============================================
# DASHBOARD 3: Apache
# ==============================================
echo ""
echo "[3/4] Creando Dashboard Apache..."

curl -s -X POST "http://localhost:3000/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u $GRAFANA_USER:$GRAFANA_PASS \
    -d '{
  "dashboard": {
    "title": "VELTRO - Apache",
    "tags": ["apache", "veltro", "web"],
    "timezone": "browser",
    "schemaVersion": 36,
    "refresh": "30s",
    "panels": [
      {
        "title": "Apache Status",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "apache_up", "refId": "A"}],
        "fieldConfig": {
          "defaults": {
            "thresholds": {"steps": [{"color": "red"}, {"color": "green", "value": 1}]},
            "mappings": [{"type": "value", "value": "0", "text": "DOWN"}, {"type": "value", "value": "1", "text": "UP"}]
          }
        }
      },
      {
        "title": "Uptime",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "apache_uptime_seconds_total", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "s"}}
      },
      {
        "title": "CPU Load",
        "type": "gauge",
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0},
        "targets": [{"expr": "apache_cpuload", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "percent", "max": 100}}
      },
      {
        "title": "Requests per Second",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [{"expr": "rate(apache_accesses_total[5m])", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "reqps"}}
      },
      {
        "title": "Traffic",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [{"expr": "rate(apache_sent_kilobytes_total[5m])", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "kBs"}}
      },
      {
        "title": "Scoreboard",
        "type": "table",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
        "targets": [{"expr": "apache_scoreboard", "format": "table", "instant": true, "refId": "A"}]
      },
      {
        "title": "Workers",
        "type": "gauge",
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 16},
        "targets": [{"expr": "apache_workers", "refId": "A"}]
      }
    ]
  },
  "overwrite": true
}' > /dev/null

echo "✓ Dashboard Apache creado"

# ==============================================
# DASHBOARD 4: Backups
# ==============================================
echo ""
echo "[4/4] Creando Dashboard Backups..."

curl -s -X POST "http://localhost:3000/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u $GRAFANA_USER:$GRAFANA_PASS \
    -d '{
  "dashboard": {
    "title": "VELTRO - Backups",
    "tags": ["backup", "veltro", "storage"],
    "timezone": "browser",
    "schemaVersion": 36,
    "refresh": "1m",
    "panels": [
      {
        "title": "MySQL Backup Size",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "backup_mysql_size_bytes", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "bytes"}}
      },
      {
        "title": "Fileserver Backup Size",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "backup_fileserver_size_bytes", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "bytes"}}
      },
      {
        "title": "Total Backups",
        "type": "stat",
        "gridPos": {"h": 4, "w": 4, "x": 12, "y": 0},
        "targets": [{"expr": "backup_total_count", "refId": "A"}]
      },
      {
        "title": "Last Backup",
        "type": "stat",
        "gridPos": {"h": 4, "w": 4, "x": 16, "y": 0},
        "targets": [{"expr": "time() - backup_last_timestamp_seconds", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "s"}}
      },
      {
        "title": "MySQL Backup Evolution",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [{"expr": "backup_mysql_size_bytes", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "bytes"}}
      },
      {
        "title": "Fileserver Backup Evolution",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [{"expr": "backup_fileserver_size_bytes", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "bytes"}}
      }
    ]
  },
  "overwrite": true
}' > /dev/null

echo "✓ Dashboard Backups creado"

echo ""
echo "=== DASHBOARDS CONFIGURADOS ==="
echo "- VELTRO - MySQL"
echo "- VELTRO - System"
echo "- VELTRO - Apache"
echo "- VELTRO - Backups"
echo ""
echo "📊 Acceso: http://localhost:3000 (admin / Gr4f4n4_V3ltr0_2025!)"