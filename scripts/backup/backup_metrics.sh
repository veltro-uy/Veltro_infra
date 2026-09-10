#!/bin/bash
# VELTRO - Métricas de backup para Node Exporter
# Actualiza métricas de tamaño y estado de backups

BACKUP_DIR="/backup"
METRICS_DIR="/var/lib/node_exporter/textfile"
METRICS_FILE="$METRICS_DIR/backup.prom"

# Crear directorio si no existe
mkdir -p $METRICS_DIR

# Calcular tamaño de backups MySQL (en bytes)
MYSQL_BACKUP_SIZE=$(find $BACKUP_DIR/database/full -name "*.sql.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')

# Calcular tamaño de backups Fileserver (en bytes)
FS_BACKUP_SIZE=$(find $BACKUP_DIR/fileserver/full -name "*.tar.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')

# Obtener timestamp del último backup
LAST_BACKUP=$(find $BACKUP_DIR/database/full -name "*.sql.gz" -type f 2>/dev/null -printf "%T@\n" | sort -n | tail -1)

# Contar número total de backups
BACKUP_COUNT=$(find $BACKUP_DIR -name "*.sql.gz" -type f 2>/dev/null | wc -l)

# Valores por defecto si no hay datos
MYSQL_BACKUP_SIZE=${MYSQL_BACKUP_SIZE:-0}
FS_BACKUP_SIZE=${FS_BACKUP_SIZE:-0}
LAST_BACKUP=${LAST_BACKUP:-0}
BACKUP_COUNT=${BACKUP_COUNT:-0}

# Escribir métricas en formato Prometheus
cat > $METRICS_FILE << EOF
# HELP backup_mysql_size_bytes Tamaño total de backups MySQL
# TYPE backup_mysql_size_bytes gauge
backup_mysql_size_bytes $MYSQL_BACKUP_SIZE

# HELP backup_fileserver_size_bytes Tamaño total de backups Fileserver
# TYPE backup_fileserver_size_bytes gauge
backup_fileserver_size_bytes $FS_BACKUP_SIZE

# HELP backup_last_timestamp_seconds Timestamp del último backup exitoso
# TYPE backup_last_timestamp_seconds gauge
backup_last_timestamp_seconds $LAST_BACKUP

# HELP backup_total_count Número total de backups realizados
# TYPE backup_total_count counter
backup_total_count $BACKUP_COUNT

# HELP backup_scrape_timestamp_seconds Momento de la última actualización
# TYPE backup_scrape_timestamp_seconds gauge
backup_scrape_timestamp_seconds $(date +%s)
EOF

echo "Métricas actualizadas: MySQL=${MYSQL_BACKUP_SIZE} bytes, Fileserver=${FS_BACKUP_SIZE} bytes, Backups=${BACKUP_COUNT}"