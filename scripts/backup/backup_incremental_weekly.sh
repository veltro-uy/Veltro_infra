#!/bin/bash
################################################################################
# VELTRO - BACKUP INCREMENTAL SEMANAL
################################################################################

set -e

BACKUP_BASE="/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WEEK=$(date +%Y_W%V)
LOG_FILE="/var/log/backup/incremental_${TIMESTAMP}.log"

MASTER_HOST="192.168.20.20"
MASTER_USER="root"
MASTER_PASS="MasterDB_V3ltr0_2025!"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p $BACKUP_BASE/database/incremental/$WEEK

exec > >(tee -a $LOG_FILE) 2>&1

echo "=============================================="
echo "  BACKUP INCREMENTAL SEMANAL - $WEEK"
echo "  Inicio: $(date)"
echo "=============================================="

# Flush logs
echo ""
echo "[1/2] Flushing binary logs..."
mysql -h $MASTER_HOST -u$MASTER_USER -p$MASTER_PASS -e "FLUSH BINARY LOGS;" 2>/dev/null
echo -e "${GREEN}✓ Binary logs flushed${NC}"

# Guardar información de binlogs
echo ""
echo "[2/2] Guardando metadata..."
mysql -h $MASTER_HOST -u$MASTER_USER -p$MASTER_PASS -e "SHOW MASTER STATUS\G" > "$BACKUP_BASE/database/incremental/$WEEK/master_status_${TIMESTAMP}.txt"
mysql -h $MASTER_HOST -u$MASTER_USER -p$MASTER_PASS -N -e "SHOW BINARY LOGS;" > "$BACKUP_BASE/database/incremental/$WEEK/binlogs_list_${TIMESTAMP}.txt"

echo -e "${GREEN}✓ Metadata guardada${NC}"

echo ""
echo "=== BACKUP INCREMENTAL COMPLETADO - $(date) ==="