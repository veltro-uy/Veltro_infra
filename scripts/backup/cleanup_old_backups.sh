#!/bin/bash
################################################################################
# VELTRO - LIMPIEZA DE BACKUPS ANTIGUOS
################################################################################

set -e

BACKUP_BASE="/backup"
LOG_FILE="/var/log/backup/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Políticas de retención (días)
RETENTION_MONTHLY=180   # 6 meses
RETENTION_WEEKLY=56     # 8 semanas
RETENTION_LOGS=90       # 3 meses

exec > >(tee -a $LOG_FILE) 2>&1

echo "=== LIMPIEZA DE BACKUPS ANTIGUOS - $(date) ==="
echo ""

# Limpiar backups mensuales (> 6 meses)
echo "1. Eliminando backups mensuales antiguos (> $RETENTION_MONTHLY días)..."
find $BACKUP_BASE/database/full -name "*.sql.gz" -mtime +$RETENTION_MONTHLY -exec rm -fv {} \;
find $BACKUP_BASE/fileserver/full -name "*.tar.gz" -mtime +$RETENTION_MONTHLY -exec rm -fv {} \;

# Limpiar backups semanales (> 8 semanas)
echo "2. Eliminando backups semanales antiguos (> $RETENTION_WEEKLY días)..."
find $BACKUP_BASE/database/incremental -type f -mtime +$RETENTION_WEEKLY -exec rm -fv {} \;
find $BACKUP_BASE/fileserver/incremental -type f -mtime +$RETENTION_WEEKLY -exec rm -fv {} \;

# Limpiar logs antiguos
echo "3. Eliminando logs antiguos (> $RETENTION_LOGS días)..."
find /var/log/backup -name "*.log" -mtime +$RETENTION_LOGS -exec rm -fv {} \;

# Limpiar directorios vacíos
echo "4. Limpiando directorios vacíos..."
find $BACKUP_BASE -type d -empty -delete 2>/dev/null || true

echo ""
echo "=== LIMPIEZA COMPLETADA - $(date) ==="