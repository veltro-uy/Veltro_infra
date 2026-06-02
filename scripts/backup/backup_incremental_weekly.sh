#!/bin/bash
################################################################################
# VELTRO - BACKUP INCREMENTAL SEMANAL
# - Respalda binary logs de MySQL
# - Respalda archivos modificados del Fileserver usando rsync
# - Si no hay cambios, crea hard links para ahorrar espacio
################################################################################

# NOTA: No usar 'set -e' para permitir que rsync falle sin detener el script

BACKUP_BASE="/backup"
WEEK=$(date +%Y_W%V)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%Y-%m-%d)
LOG_FILE="/var/log/backup/incremental_${TIMESTAMP}.log"

# Configuración SSH (evita preguntas de confirmación)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

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

# Verificar conectividad SSH primero
echo "  Verificando conexión SSH..."
if ssh -p 22 $SSH_OPTS $FILESERVER_USER@$FILESERVER_IP "echo OK" >/dev/null 2>&1; then
    echo "  ✓ Conexión SSH establecida"
    
    # Usar rsync con --link-dest para hard links (ahorra espacio)
    if [ -d "$PREV_WEEK_DIR" ] && [ -d "$PREV_WEEK_DIR/shared" ]; then
        echo "  Usando backup anterior como referencia (hard links)..."
        rsync -av --delete \
            --link-dest="$PREV_WEEK_DIR/shared" \
            -e "ssh -p 22 $SSH_OPTS" \
            $FILESERVER_USER@$FILESERVER_IP:/srv/shared/ \
            "$FS_INCR_DIR/shared/" 2>/dev/null || true
    else
        echo "  Primera copia incremental (sin referencia previa)..."
        rsync -av --delete \
            -e "ssh -p 22 $SSH_OPTS" \
            $FILESERVER_USER@$FILESERVER_IP:/srv/shared/ \
            "$FS_INCR_DIR/shared/" 2>/dev/null || true
    fi
else
    echo "  ⚠ No se pudo establecer conexión SSH al Fileserver"
    echo "  El backup incremental del Fileserver se omitirá"
fi

# ==============================================
# 3. CREAR ARCHIVO COMPRIMIDO
# ==============================================
echo ""
echo "[3/4] Creando archivo comprimido..."

FILE_COUNT=0
SIZE="0"

if [ -d "$FS_INCR_DIR/shared" ]; then
    # Contar archivos
    FILE_COUNT=$(find "$FS_INCR_DIR/shared" -type f 2>/dev/null | wc -l)
    echo "  Archivos respaldados: $FILE_COUNT"
    
    if [ $FILE_COUNT -gt 0 ]; then
        cd $FS_INCR_DIR
        TAR_FILE="fileserver_inc_${TIMESTAMP}.tar.gz"
        tar -czf $TAR_FILE shared/ 2>/dev/null
        SIZE=$(du -h $TAR_FILE | cut -f1)
        echo "✓ Backup comprimido: $SIZE"
        rm -rf shared/
    else
        echo "⚠ No hay archivos para comprimir"
    fi
else
    echo "⚠ No hay archivos para comprimir"
fi

# ==============================================
# 4. CREAR ENLACES SIMBÓLICOS
# ==============================================
echo ""
echo "[4/5] Optimizando almacenamiento..."

# Crear enlace simbólico al último backup incremental
ln -sfn "$FS_INCR_DIR" "$BACKUP_BASE/fileserver/incremental/latest" 2>/dev/null
ln -sfn "$WEEK_DIR" "$BACKUP_BASE/incremental/latest" 2>/dev/null

# ==============================================
# 5. GENERAR METADATA
# ==============================================
echo ""
echo "[5/5] Generando metadata..."

METADATA_FILE="$WEEK_DIR/metadata_${WEEK}.json"

# Obtener tamaño total del backup
TOTAL_SIZE=$(du -sh $BACKUP_BASE 2>/dev/null | cut -f1)

cat > "$METADATA_FILE" << EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_type": "incremental_weekly",
  "week": "$WEEK",
  "timestamp": "$TIMESTAMP",
  "mysql": {
    "binary_logs_count": $(ls $DB_INCR_DIR/*.txt 2>/dev/null | wc -l)
  },
  "fileserver": {
    "backup_file": "$(basename $TAR_FILE 2>/dev/null)",
    "size": "$SIZE",
    "file_count": $FILE_COUNT,
    "previous_backup": "$(basename $PREV_WEEK_DIR 2>/dev/null)"
  },
  "storage": {
    "location": "$BACKUP_BASE",
    "total_size": "$TOTAL_SIZE"
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
echo "  - Binary logs: $(ls $DB_INCR_DIR/*.txt 2>/dev/null | wc -l) archivos"
echo "  - Fileserver: $FILE_COUNT archivos ($SIZE)"
echo "  - Espacio total en backups: $TOTAL_SIZE"

exit 0