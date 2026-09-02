#!/bin/bash
################################################################################
# VELTRO - Configuración del Servidor de Backup
# Ejecutado automáticamente al levantar el contenedor
################################################################################

set -e

echo "=========================================="
echo "  VELTRO BACKUP SERVER - INICIANDO"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Instalar paquetes
log "Instalando paquetes..."
dnf install -y rsync mysql cronie openssh-server openssh-clients sshpass \
    tar gzip bzip2 pigz vim less htop wget curl \
    procps-ng net-tools lsof telnet nc iputils sudo

# 2. Instalar Node Exporter
if [ ! -f /usr/local/bin/node_exporter ]; then
    log "Instalando Node Exporter..."
    cd /tmp
    curl -L --retry 3 -o node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    tar xzf node_exporter.tar.gz
    cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
    rm -rf node_exporter-1.7.0.linux-amd64*
    log "✓ Node Exporter instalado"
fi

mkdir -p /var/lib/node_exporter/textfile
chmod 755 /var/lib/node_exporter/textfile

# 3. Configurar SSH Server
log "Configurando SSH..."
ssh-keygen -A
mkdir -p /var/run/sshd

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
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

# 4. Crear usuario backup
if ! id backup &>/dev/null; then
    log "Creando usuario backup..."
    useradd -m -G wheel backup
    echo "backup:B4ckup_V3ltr0_2025!" | chpasswd
    log "✓ Usuario backup creado"
fi

mkdir -p /home/backup/.ssh
chmod 700 /home/backup/.ssh
chown -R backup:backup /home/backup/.ssh

# Configurar sudo sin contraseña
echo "backup ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/backup

# 5. Generar clave SSH para backup (si no existe)
if [ ! -f /home/backup/.ssh/id_rsa ]; then
    log "Generando clave SSH para backup..."
    su - backup -c "ssh-keygen -t rsa -b 4096 -f /home/backup/.ssh/id_rsa -N '' -q"
    log "✓ Clave SSH generada"
fi

# Agregar clave pública a authorized_keys propio (SIEMPRE, para asegurar)
su - backup -c "cat /home/backup/.ssh/id_rsa.pub > /home/backup/.ssh/authorized_keys"
chmod 600 /home/backup/.ssh/authorized_keys
chown -R backup:backup /home/backup/.ssh

log "✓ Clave SSH configurada"

# NOTA: la instalación de esta clave en el File Server YA NO se hace acá.
# Se instala automáticamente desde el host, después de docker-compose up,
# mediante scripts/init/setup-ssh-config.sh (usa 'docker exec', no SSH,
# por lo que no depende de PasswordAuthentication ni de resolución DNS
# entre redes Docker distintas). Esto elimina el bloque que antes
# reiniciaba el contenedor en loop por el fallo de 'ssh-keyscan -H fileserver'.

# 6. Estructura de directorios
log "Creando estructura de directorios..."
mkdir -p /backup/database/full /backup/database/incremental
mkdir -p /backup/fileserver/full
mkdir -p /backup/metadata /backup/temp /backup/weekly /backup/monthly
mkdir -p /var/log/backup
chmod -R 755 /backup
chown -R backup:backup /backup

# 7. Script de métricas
log "Creando script de métricas..."
cat > /usr/local/bin/backup_metrics.sh << 'METRICS'
#!/bin/bash
BACKUP_DIR="/backup"
METRICS_DIR="/var/lib/node_exporter/textfile"
METRICS_FILE="$METRICS_DIR/backup.prom"

mkdir -p $METRICS_DIR

MYSQL_BACKUP_SIZE=$(find $BACKUP_DIR/database/full -name "*.sql.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')
FS_BACKUP_SIZE=$(find $BACKUP_DIR/fileserver/full -name "*.tar.gz" -type f 2>/dev/null -exec du -sb {} \; | awk '{sum+=$1} END {print sum}')
BACKUP_COUNT=$(find $BACKUP_DIR -name "*.sql.gz" -type f 2>/dev/null | wc -l)

MYSQL_BACKUP_SIZE=${MYSQL_BACKUP_SIZE:-0}
FS_BACKUP_SIZE=${FS_BACKUP_SIZE:-0}
BACKUP_COUNT=${BACKUP_COUNT:-0}

cat > $METRICS_FILE << EOM
# HELP backup_mysql_size_bytes Tamaño total de backups MySQL
# TYPE backup_mysql_size_bytes gauge
backup_mysql_size_bytes $MYSQL_BACKUP_SIZE
# HELP backup_fileserver_size_bytes Tamaño total de backups Fileserver
# TYPE backup_fileserver_size_bytes gauge
backup_fileserver_size_bytes $FS_BACKUP_SIZE
# HELP backup_total_count Número total de backups realizados
# TYPE backup_total_count counter
backup_total_count $BACKUP_COUNT
EOM
METRICS

chmod +x /usr/local/bin/backup_metrics.sh

# Ejecutar métricas iniciales
/usr/local/bin/backup_metrics.sh

# 8. Configurar crontab
log "Configurando tareas programadas..."
export HOME=/home/backup
mkdir -p /home/backup/.cache
chown -R backup:backup /home/backup/.cache
su - backup -c "crontab -r 2>/dev/null || true"
su - backup -c "(crontab -l 2>/dev/null; echo '0 2 1 * * /bin/bash /scripts/backup_full_monthly.sh >> /var/log/backup/full_\$(date +\%Y\%m\%d).log 2>&1') | crontab -"
su - backup -c "(crontab -l 2>/dev/null; echo '*/5 * * * * /usr/local/bin/backup_metrics.sh') | crontab -"
log "✓ Crontab configurado"

# 9. Iniciar servicios
log "Iniciando servicios..."
/usr/sbin/sshd
/usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile &

log "✓ Servicios iniciados"
log "Backup Server listo."

# 10. Mantener el contenedor vivo
while true; do
    if ! pgrep -x sshd > /dev/null; then
        /usr/sbin/sshd
    fi
    if ! pgrep -x node_exporter > /dev/null; then
        /usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile &
    fi
    sleep 30
done
