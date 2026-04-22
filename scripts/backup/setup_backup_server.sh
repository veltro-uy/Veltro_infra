#!/bin/bash
################################################################################
# VELTRO - Configuración del Servidor de Backup con SSH y Node Exporter
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
dnf install -y rsync mysql cronie openssh-server openssh-clients \
    tar gzip bzip2 pigz vim less htop wget \
    procps-ng net-tools lsof telnet nc sshpass iputils

# 2. Instalar Node Exporter
log "Instalando Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# 3. Configurar SSH Server
log "Configurando SSH Server..."
ssh-keygen -A
mkdir -p /var/run/sshd
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Configurar sshd_config correctamente
cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication yes
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

# Establecer contraseña de root
echo "root:B4ckupR00t_V3ltr0_2025!" | chpasswd
log "✓ SSH Server configurado"

# 4. Generar clave SSH para acceso al File Server
log "Generando clave SSH para acceso al File Server..."
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
log "✓ Clave SSH generada"

# 5. Configurar acceso al File Server (IP fija)
log "Configurando acceso al File Server..."
FILESERVER_LAN_IP="192.168.0.100"

# Eliminar entrada existente si existe
sed -i '/fileserver/d' /etc/hosts 2>/dev/null || true

# Agregar nueva entrada
echo "$FILESERVER_LAN_IP fileserver" >> /etc/hosts
log "✓ Entrada en /etc/hosts agregada: $FILESERVER_LAN_IP fileserver"

# 6. Crear estructura de directorios
log "Creando estructura de directorios..."
mkdir -p /var/log/backup
mkdir -p /backup/{weekly,monthly,database,files,metadata,temp}
mkdir -p /backup/database/{full,incremental}
mkdir -p /backup/files/{full,incremental}
chmod -R 755 /backup

# 7. Configurar crontab
log "Configurando tareas programadas..."
crontab -r 2>/dev/null || true
(crontab -l 2>/dev/null; echo '0 2 1 * * /bin/bash /scripts/backup_full_monthly.sh >> /var/log/backup/full_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 3 * * 0 /bin/bash /scripts/backup_incremental_weekly.sh >> /var/log/backup/incremental_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 4 * * * /bin/bash /scripts/cleanup_old_backups.sh >> /var/log/backup/cleanup_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '0 5 * * * /bin/bash /scripts/check_backup_integrity.sh >> /var/log/backup/check_$(date +\%Y\%m\%d_\%H\%M\%S).log 2>&1') | crontab -

# 8. Iniciar servicios
log "Iniciando servicios..."
/usr/sbin/sshd
/usr/local/bin/node_exporter --web.listen-address=:9100 &
crond -n

echo "=========================================="
echo "  BACKUP SERVER LISTO"
echo "=========================================="