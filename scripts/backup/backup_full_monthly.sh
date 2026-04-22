#!/bin/bash
################################################################################
# VELTRO - BACKUP COMPLETO MENSUAL
################################################################################

set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuración
BACKUP_BASE="/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%Y%m)
LOG_FILE="/var/log/backup/full_${TIMESTAMP}.log"

# Credenciales
MASTER_HOST="192.168.20.20"
MASTER_USER="root"
MASTER_PASS="MasterDB_V3ltr0_2025!"

# Crear directorios
mkdir -p $BACKUP_BASE/database/full/$MONTH
mkdir -p $BACKUP_BASE/fileserver/full/$MONTH
mkdir -p $BACKUP_BASE/metadata

exec > >(tee -a $LOG_FILE) 2>&1

echo "=============================================="
echo "  BACKUP COMPLETO MENSUAL - $MONTH"
echo "  Inicio: $(date)"
echo "=============================================="

# Backup MySQL
echo ""
echo "[1/4] Backup de MySQL..."
MYSQL_BACKUP="$BACKUP_BASE/database/full/$MONTH/veltro_master_${TIMESTAMP}.sql.gz"

if mysqldump -h $MASTER_HOST -u$MASTER_USER -p$MASTER_PASS \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --all-databases \
    --flush-logs \
    --master-data=2 \
    | gzip > "$MYSQL_BACKUP"; then
    
    SIZE=$(du -h "$MYSQL_BACKUP" | cut -f1)
    echo -e "${GREEN}✓ Backup MySQL: $SIZE${NC}"
    
    md5sum "$MYSQL_BACKUP" > "${MYSQL_BACKUP}.md5"
else
    echo -e "${RED}✗ Error en backup MySQL${NC}"
    exit 1
fi

# Backup Fileserver
echo ""
echo "[2/4] Backup de Fileserver..."
FILESERVER_BACKUP="$BACKUP_BASE/fileserver/full/$MONTH/fileserver_full_${TIMESTAMP}.tar.gz"

# Verificar conectividad SSH
if ssh -o ConnectTimeout=5 -p 2222 root@host.docker.internal "echo ok" 2>/dev/null; then
    ssh -p 2222 root@host.docker.internal "tar -czf - -C /srv shared" > "$FILESERVER_BACKUP" 2>/dev/null
    
    if [ -s "$FILESERVER_BACKUP" ]; then
        SIZE=$(du -h "$FILESERVER_BACKUP" | cut -f1)
        echo -e "${GREEN}✓ Backup Fileserver: $SIZE${NC