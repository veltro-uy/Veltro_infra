#!/bin/bash
################################################################################
# VELTRO - BACKUP COMPLETO MENSUAL
################################################################################

set -e

BACKUP_BASE="/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%Y%m)

echo "=============================================="
echo "  BACKUP COMPLETO MENSUAL - $MONTH"
echo "  Inicio: $(date)"
echo "=============================================="

# Backup MySQL
echo ""
echo "[1/3] Backup de MySQL..."
MYSQL_BACKUP="$BACKUP_BASE/database/full/$MONTH/veltro_master_${TIMESTAMP}.sql.gz"
mkdir -p "$BACKUP_BASE/database/full/$MONTH"

mysqldump -h 192.168.20.20 -uroot -pMasterDB_V3ltr0_2025! \
    --single-transaction --routines --triggers --events --all-databases \
    2>/dev/null | gzip > "$MYSQL_BACKUP"

echo "✓ Backup MySQL: $(du -h $MYSQL_BACKUP | cut -f1)"
md5sum "$MYSQL_BACKUP" > "${MYSQL_BACKUP}.md5"

# Backup Fileserver
echo ""
echo "[2/3] Backup de Fileserver..."
/scripts/backup_fileserver.sh

# Backup binary logs
echo ""
echo "[3/3] Respaldando binary logs..."
BINLOGS_DIR="$BACKUP_BASE/database/full/$MONTH/binlogs_${TIMESTAMP}"
mkdir -p "$BINLOGS_DIR"
mysql -h 192.168.20.20 -uroot -pMasterDB_V3ltr0_2025! -e "SHOW MASTER STATUS\G" 2>/dev/null > "$BINLOGS_DIR/master_status.txt"
echo "✓ Binary logs metadata guardada"

echo ""
echo "=============================================="
echo "  BACKUP COMPLETO FINALIZADO - $(date)"
echo "=============================================="