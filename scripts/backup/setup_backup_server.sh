#!/bin/bash
################################################################################
# VELTRO - Configuración del Servidor de Backup
# Idempotente: puede ejecutarse múltiples veces sin errores
################################################################################

set -e

echo "=========================================="
echo "  VELTRO BACKUP SERVER - INICIANDO"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Instalar paquetes necesarios
log "Instalando paquetes necesarios..."
dnf install -y rsync mysql cronie openssh-server openssh-clients sshpass \
    tar gzip bzip2 pigz vim less htop wget curl \
    procps-ng net-tools lsof telnet nc iputils sudo

# 2. Instalar Node Exporter (solo si no existe)
if [ ! -f /usr/local/bin/node_exporter ]; then
    log "Instalando Node Exporter..."
    cd /tmp
    curl -L --fail --retry 3 -o node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    if [ -f node_exporter.tar.gz ] && [ -s node_exporter.tar.gz ]; then
        tar xzf node_exporter.tar.gz
        cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
        rm -rf node_exporter-1.7.0.linux-amd64*
        log "✓ Node Exporter instalado"
    else
        log "ERROR: No se pudo descargar Node Exporter"
        exit 1
    fi
else
    log "✓ Node Exporter ya instalado"
fi

# Crear directorio para textfile collector
mkdir -p /var/lib/node_exporter/textfile
chmod 755 /var/lib/node_exporter/textfile

# 3. Configurar SSH Server (solo si no está configurado)
if ! grep -q "PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
    log "Configurando SSH Server..."
    ssh-keygen -A
    mkdir -p /var/run/sshd
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
fi

cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

# 4. Crear usuario backup (si no existe)
if ! id backup &>/dev/null; then
    log "Creando usuario backup..."
    useradd -m -G wheel backup
    echo "backup:B4ckup_V3ltr0_2025!" | chpasswd
    log "✓ Usuario backup creado"
else
    log "✓ Usuario backup ya existe"
fi

# Configurar directorio .ssh para backup
mkdir -p /home/backup/.ssh
chmod 700 /home/backup/.ssh
chown -R backup:backup /home/backup/.ssh

# Configurar sudo sin contraseña (si no existe)
if [ ! -f /etc/sudoers.d/backup ]; then
    echo "backup ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/backup
    log "✓ Sudo configurado para backup"
fi

# 5. Generar clave SSH para backup (si no existe)
if [ ! -f /home/backup/.ssh/id_rsa ]; then
    log "Generando clave SSH para backup..."
    su - backup -c "ssh-keygen -t rsa -b 4096 -f /home/backup/.ssh/id_rsa -N '' -q"
    log "✓ Clave SSH generada"
else
    log "✓ Clave SSH ya existe"
fi

# Agregar clave pública a authorized_keys (si no está)
if ! grep -q "$(cat /home/backup/.ssh/id_rsa.pub)" /home/backup/.ssh/authorized_keys 2>/dev/null; then
    cat /home/backup/.ssh/id_rsa.pub >> /home/backup/.ssh/authorized_keys
    chmod 600 /home/backup/.ssh/authorized_keys
    log "✓ Clave agregada a authorized_keys"
fi

chown -R backup:backup /home/backup/.ssh

# 6. Configurar acceso al Fileserver (opcional, no crítico)
log "Configurando acceso al Fileserver..."
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
FILESERVER_PORT="2322"

# Agregar entrada en /etc/hosts (si no existe)
if ! grep -q "$FILESERVER_IP fileserver" /etc/hosts 2>/dev/null; then
    echo "$FILESERVER_IP fileserver" >> /etc/hosts
    log "✓ Entrada en /etc/hosts agregada"
fi

# 7. Crear estructura de directorios (si no existe)
if [ ! -d /backup/database/full ]; then
    log "Creando estructura de directorios..."
    mkdir -p /var/log/backup
    mkdir -p /backup/{weekly,monthly,database,files,metadata,temp}
    mkdir -p /backup/database/{full,incremental}
    mkdir -p /backup/files/{full,incremental}
    mkdir -p /backup/fileserver/full
    chmod -R 755 /backup
    chown -R backup:backup /backup
    log "✓ Directorios creados"
else
    log "✓ Directorios ya existen"
fi

# 8. Script de métricas (si no existe)
if [ ! -f /usr/local/bin/backup_metrics.sh ]; then
    log "Creando script de métricas..."
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
EOM
echo "Métricas actualizadas"
METRICSSCRIPT

    chmod +x /usr/local/bin/backup_metrics.sh
    log "✓ Script de métricas creado"
else
    log "✓ Script de métricas ya existe"
fi

# Ejecutar métricas iniciales
/usr/local/bin/backup_metrics.sh

# 9. Configurar crontab para backup (solo si no existe)
if ! su - backup -c "crontab -l 2>/dev/null | grep -q backup_metrics"; then
    log "Configurando tareas programadas..."
    su - backup -c "crontab -r 2>/dev/null || true"
    su - backup -c "(crontab -l 2>/dev/null; echo '0 2 1 * * /bin/bash /scripts/backup_full_monthly.sh >> /var/log/backup/full_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -"
    su - backup -c "(crontab -l 2>/dev/null; echo '*/5 * * * * /usr/local/bin/backup_metrics.sh') | crontab -"
    log "✓ Crontab configurado"
else
    log "✓ Crontab ya configurado"
fi

# 10. Iniciar servicios
log "Iniciando servicios..."
/usr/sbin/sshd
/usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile &

log "✓ Servicios iniciados"

# 11. Mantener el contenedor vivo (CRÍTICO)
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