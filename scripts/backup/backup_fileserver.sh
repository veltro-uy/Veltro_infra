#!/bin/bash
################################################################################
# VELTRO - Backup del File Server (usando IP directa)
################################################################################

#!/bin/bash
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
DATE=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%Y%m)
BACKUP_DIR="/backup/fileserver/full/$MONTH"
mkdir -p $BACKUP_DIR

echo "=== Backup de Fileserver ==="

# Backup de toda la estructura /srv/shared
ssh -p 22 $FILESERVER_USER@$FILESERVER_IP "tar -czf - -C /srv shared 2>/dev/null" > $BACKUP_DIR/fileserver_full_${DATE}.tar.gz

if [ -s "$BACKUP_DIR/fileserver_full_${DATE}.tar.gz" ]; then
    SIZE=$(du -h $BACKUP_DIR/fileserver_full_${DATE}.tar.gz | cut -f1)
    echo "✓ Backup Fileserver: $SIZE"
    
    # Mostrar contenido del backup
    echo "  Contenido:"
    tar -tzf $BACKUP_DIR/fileserver_full_${DATE}.tar.gz 2>/dev/null | head -10 | sed 's/^/    /'
    
    md5sum $BACKUP_DIR/fileserver_full_${DATE}.tar.gz > $BACKUP_DIR/fileserver_full_${DATE}.tar.gz.md5
else
    echo "⚠ No se pudo crear el backup del Fileserver"
fi