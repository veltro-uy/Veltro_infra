#!/bin/bash
################################################################################
# VELTRO - BACKUP INCREMENTAL SEMANAL
# - Respalda binary logs de MySQL
# - Respalda archivos modificados del Fileserver usando rsync
# - Si no hay cambios, crea hard links para ahorrar espacio
################################################################################

set -e

BACKUP_BASE="/backup"
WEEK=$(date +%Y_W%V)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%Y-%m-%d)
LOG_FILE="/var/log/backup/incremental_${TIMESTAMP}.log"

# Configuración Fileserver
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"

# Directorios
WEEK_DIR="$BACKUP_BASE/incremental/$WEEK"
DB_INCR_DIR="$BACKUP_BASE/database/incremental/$WEEK"
FS_INCR_DIR="$BACKUP_BASE/fileserver/incremental/$WEEK"
PREV_WEEK_DIR="$BACKUP_BASE/incremental/$(date -d 'last week' +%Y_W%V 2>/dev/null || echo 'none')"

mkdir -p $DB_INCR_DIR
mkdir -p $FS_INCR_DIR
mkdir -p $WEEK_DIR

exec > >(tee -a $LOG_FILE) 2>&1

echo "=============================================="
echo "  BACKUP INCREMENTAL SEMANAL - Semana $WEEK"
echo "  Fecha: $DATE"
echo "  Inicio: $(date)"
echo "=============================================="

# ==============================================
# 1. RESPALDO DE BINARY LOGS (MySQL)
# ==============================================
echo ""
echo "[1/3] Respaldando binary logs de MySQL..."

# Flush logs para crear un nuevo archivo
mysql -h 192.168.20.20 -uroot -pMasterDB_V3ltr0_2025! -e "FLUSH BINARY LOGS;" 2>/dev/null

# Guardar metadata de binlogs
mysql -h 192.168.20.20 -uroot -pMasterDB_V3ltr0_2025! -e "SHOW MASTER STATUS\G" 2>/dev/null > "$DB_INCR_DIR/master_status_${TIMESTAMP}.txt"
mysql -h 192.168.20.20 -uroot -pMasterDB_V3ltr0_2025! -e "SHOW BINARY LOGS;" 2>/dev/null > "$DB_INCR_DIR/binlogs_list_${TIMESTAMP}.txt"

# Obtener lista de binary logs desde el último backup
LAST_BACKUP=$(find $BACKUP_BASE/database/full -name "*.sql.gz" -type f 2>/dev/null | sort -r | head -1)
if [ -n "$LAST_BACKUP" ]; then
    LAST_DATE=$(stat -c %y "$LAST_BACKUP" 2>/dev/null | cut -d' ' -f1)
    echo "  Último backup completo: $LAST_DATE"
fi

echo "✓ Binary logs metadata guardada"

# ==============================================
# 2. RESPALDO INCREMENTAL DEL FILESERVER
# ==============================================
echo ""
echo "[2/3] Respaldando archivos modificados del Fileserver..."

# Crear directorio para esta semana
mkdir -p "$FS_INCR_DIR"

# Usar rsync con --link-dest para hard links (ahorra espacio)
if [ -d "$PREV_WEEK_DIR" ] && [ -d "$PREV_WEEK_DIR/shared" ]; then
    # Si existe backup anterior, usar --link-dest
    echo "  Usando backup anterior como referencia (hard links)..."
    rsync -av --delete \
        --link-dest="$PREV_WEEK_DIR/shared" \
        -e "ssh -p 22" \
        $FILESERVER_USER@$FILESERVER_IP:/srv/shared/ \
        "$FS_INCR_DIR/shared/" 2>/dev/null
else
    # Primera vez, copiar todo
    echo "  Primera copia incremental (sin referencia previa)..."
    rsync -av --delete \
        -e "ssh -p 22" \
        $FILESERVER_USER@$FILESERVER_IP:/srv/shared/ \
        "$FS_INCR_DIR/shared/" 2>/dev/null
fi

# Crear archivo comprimido de los cambios
if [ -d "$FS_INCR_DIR/shared" ]; then
    # Listar archivos modificados esta semana
    echo "  Archivos modificados esta semana:" > "$FS_INCR_DIR/changed_files_${TIMESTAMP}.txt"
    find "$FS_INCR_DIR/shared" -type f -newer "$PREV_WEEK_DIR" 2>/dev/null | head -50 >> "$FS_INCR_DIR/changed_files_${TIMESTAMP}.txt"
    
    # Contar archivos
    FILE_COUNT=$(find "$FS_INCR_DIR/shared" -type f 2>/dev/null | wc -l)
    echo "  Total archivos respaldados: $FILE_COUNT"
    
    # Crear tar.gz con timestamp
    tar -czf "$FS_INCR_DIR/fileserver_inc_${TIMESTAMP}.tar.gz" -C "$FS_INCR_DIR" shared 2>/dev/null
    SIZE=$(du -h "$FS_INCR_DIR/fileserver_inc_${TIMESTAMP}.tar.gz" | cut -f1)
    echo "✓ Backup incremental Fileserver: $SIZE"
    
    # Calcular espacio ahorrado con hard links
    if [ -d "$PREV_WEEK_DIR" ]; then
        ORIGINAL_SIZE=$(du -sb "$FS_INCR_DIR/shared" 2>/dev/null | cut -f1)
        TAR_SIZE=$(stat -c %s "$FS_INCR_DIR/fileserver_inc_${TIMESTAMP}.tar.gz" 2>/dev/null)
        if [ -n "$ORIGINAL_SIZE" ] && [ -n "$TAR_SIZE" ] && [ $TAR_SIZE -gt 0 ]; then
            SAVED=$((ORIGINAL_SIZE - TAR_SIZE))
            echo "  Espacio ahorrado con hard links: $(numfmt --to=iec $SAVED 2>/dev/null || echo $SAVED bytes)"
        fi
    fi
    
    # No eliminar shared/ para futuros --link-dest
else
    echo "⚠ No se pudo conectar al Fileserver"
fi

# ==============================================
# 3. CREAR ESTRUCTURA CON HARDLINKS PARA AHORRAR ESPACIO
# ==============================================
echo ""
echo "[3/3] Optimizando almacenamiento..."

# Crear enlace simbólico al último backup incremental
ln -sfn "$FS_INCR_DIR" "$BACKUP_BASE/fileserver/incremental/latest" 2>/dev/null
ln -sfn "$WEEK_DIR" "$BACKUP_BASE/incremental/latest" 2>/dev/null

# ==============================================
# GENERAR METADATA DEL BACKUP
# ==============================================
METADATA_FILE="$WEEK_DIR/metadata_${WEEK}.json"

cat > "$METADATA_FILE" << EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_type": "incremental_weekly",
  "week": "$WEEK",
  "timestamp": "$TIMESTAMP",
  "mysql": {
    "status_file": "$(basename $DB_INCR_DIR/master_status_${TIMESTAMP}.txt)",
    "binlogs_file": "$(basename $DB_INCR_DIR/binlogs_list_${TIMESTAMP}.txt)"
  },
  "fileserver": {
    "incremental_backup": "$(basename $FS_INCR_DIR/fileserver_inc_${TIMESTAMP}.tar.gz 2>/dev/null)",
    "size": "$SIZE",
    "file_count": $FILE_COUNT,
    "previous_backup": "$(basename $PREV_WEEK_DIR 2>/dev/null)"
  },
  "storage": {
    "location": "$BACKUP_BASE",
    "total_size": "$(du -sh $BACKUP_BASE 2>/dev/null | cut -f1)"
  }
}
EOF

echo "✓ Metadata guardada: $METADATA_FILE"

# ==============================================
# RESUMEN FINAL
# ==============================================
echo ""
echo "=============================================="
echo "  BACKUP INCREMENTAL COMPLETADO - Semana $WEEK"
echo "  Fin: $(date)"
echo "=============================================="

# Mostrar resumen
echo ""
echo "Resumen:"
echo "  - Binary logs: $(ls -la $DB_INCR_DIR/*.txt 2>/dev/null | wc -l) archivos"
echo "  - Fileserver: $(du -sh $FS_INCR_DIR/fileserver_inc_*.tar.gz 2>/dev/null | wc -l) backups"
echo "  - Total backups incremental: $(du -sh $WEEK_DIR 2>/dev/null | cut -f1)"
echo "  - Espacio total en backups: $(du -sh $BACKUP_BASE 2>/dev/null | cut -f1)"

exit 0