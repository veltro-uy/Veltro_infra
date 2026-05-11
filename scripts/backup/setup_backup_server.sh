#!/bin/bash
################################################################################
# VELTRO - Configuración del Servidor de Backup
################################################################################

set -e

echo "=========================================="
echo "  VELTRO BACKUP SERVER - CONFIGURACIÓN"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# ==============================================
# 1. INSTALAR PAQUETES
# ==============================================
log "Instalando paquetes necesarios..."
dnf install -y rsync mysql cronie openssh-server openssh-clients sshpass \
    tar gzip bzip2 pigz vim less htop wget \
    procps-ng net-tools lsof telnet nc iputils

# ==============================================
# 2. INSTALAR NODE EXPORTER
# ==============================================
log "Instalando Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# Crear directorio para textfile collector
mkdir -p /var/lib/node_exporter/textfile
chmod 755 /var/lib/node_exporter/textfile

# ==============================================
# 3. CONFIGURAR SSH SERVER
# ==============================================
log "Configurando SSH Server..."
ssh-keygen -A
mkdir -p /var/run/sshd
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

echo "root:B4ckupR00t_V3ltr0_2025!" | chpasswd
log "✓ SSH Server configurado"

# ==============================================
# 4. GENERAR CLAVE SSH
# ==============================================
log "Generando clave SSH..."
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
fi
log "✓ Clave SSH generada"

# ==============================================
# 5. CONFIGURAR ACCESO AL FILESERVER
# ==============================================
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
FILESERVER_PASS="Admin_V3ltr0_2025!"

log "Configurando acceso al Fileserver ($FILESERVER_IP)..."

# Esperar a que el Fileserver esté listo
log "Esperando a que el Fileserver esté disponible..."
while ! nc -z $FILESERVER_IP 22 2>/dev/null; do
    sleep 2
done
log "✓ Fileserver disponible"

# Agregar entrada en /etc/hosts
grep -q "$FILESERVER_IP" /etc/hosts || echo "$FILESERVER_IP fileserver" >> /etc/hosts
log "✓ Entrada en /etc/hosts agregada"

# Agregar IP a known_hosts
ssh-keyscan -H $FILESERVER_IP >> /root/.ssh/known_hosts 2>/dev/null
log "✓ IP agregada a known_hosts"

# Copiar clave SSH usando sshpass
log "Copiando clave SSH al Fileserver..."
sshpass -p "$FILESERVER_PASS" ssh-copy-id -o StrictHostKeyChecking=no -p 22 $FILESERVER_USER@$FILESERVER_IP 2>/dev/null
log "✓ Clave SSH copiada"

# Probar conexión
log "Probando conexión SSH..."
if ssh -p 22 -o BatchMode=yes $FILESERVER_USER@$FILESERVER_IP "echo OK" 2>/dev/null; then
    log "✓ Conexión SSH establecida"
else
    log "⚠ No se pudo establecer conexión SSH (continuando de todos modos)"
fi

# ==============================================
# 6. CREAR ESTRUCTURA DE DIRECTORIOS
# ==============================================
log "Creando estructura de directorios..."
mkdir -p /var/log/backup
mkdir -p /backup/{weekly,monthly,database,files,metadata,temp}
mkdir -p /backup/database/{full,incremental}
mkdir -p /backup/files/{full,incremental}
mkdir -p /backup/fileserver/full
chmod -R 755 /backup

# ==============================================
# 7. CONFIGURAR CRONTAB
# ==============================================
log "Configurando tareas programadas..."
crontab -r 2>/dev/null || true
(crontab -l 2>/dev/null; echo '0 2 1 * * /bin/bash /scripts/backup_full_monthly.sh >> /var/log/backup/full_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 3 * * 0 /bin/bash /scripts/backup_incremental_weekly.sh >> /var/log/backup/incremental_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 4 * * * /bin/bash /scripts/cleanup_old_backups.sh >> /var/log/backup/cleanup_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 5 * * * /bin/bash /scripts/check_backup_integrity.sh >> /var/log/backup/check_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -

# ==============================================
# 8. CREAR SCRIPTS DE MÉTRICAS DE BACKUP
# ==============================================
log "Creando script de métricas de backup..."

cat > /usr/local/bin/backup_metrics.sh << 'METRICSSCRIPT'
#!/bin/bash
BACKUP_DIR="/backup"
METRICS_DIR="/var/lib/node_exporter/textfile"
METRICS_FILE="$METRICS_DIR/backup.prom"

mkdir -p $METRICS_DIR

MYSQL_BACKUP_SIZE=$(find $BACKUP_DIR/database/full -name "*.sql.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')
FS_BACKUP_SIZE=$(find $BACKUP_DIR/fileserver/full -name "*.tar.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')
LAST_BACKUP=$(find $BACKUP_DIR/database/full -name "*.sql.gz" -type f 2>/dev/null -printf "%T@\n" | sort -n | tail -1)
BACKUP_COUNT=$(find $BACKUP_DIR -name "*.sql.gz" -type f 2>/dev/null | wc -l)

MYSQL_BACKUP_SIZE=${MYSQL_BACKUP_SIZE:-0}
FS_BACKUP_SIZE=${FS_BACKUP_SIZE:-0}
LAST_BACKUP=${LAST_BACKUP:-0}
BACKUP_COUNT=${BACKUP_COUNT:-0}

cat > $METRICS_FILE << EOM
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
EOM

echo "Métricas actualizadas: MySQL=${MYSQL_BACKUP_SIZE} bytes, FS=${FS_BACKUP_SIZE} bytes"
METRICSSCRIPT

chmod +x /usr/local/bin/backup_metrics.sh
log "✓ Script de métricas creado"

# 8. Ejecutar métricas iniciales
log "Ejecutando métricas iniciales..."
/usr/local/bin/backup_metrics.sh
log "✓ Métricas iniciales generadas"

# ==============================================
# 9. INICIAR SERVICIOS (incluyendo métricas)
# ==============================================
log "Iniciando servicios..."
/usr/sbin/sshd
/usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile &

log "✓ Servicios iniciados"

# ==============================================
# 10. MANTENER EL CONTENEDOR VIVO
# ==============================================
log "Backup Server listo. Manteniendo servicios activos..."
while true; do
    if ! pgrep -x sshd > /dev/null; then
        log "SSH caído, reiniciando..."
        /usr/sbin/sshd
    fi
    if ! pgrep -x node_exporter > /dev/null; then
        log "Node Exporter caído, reiniciando..."
        /usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile &
    fi
    sleep 30
done