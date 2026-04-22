#!/bin/bash
################################################################################
# VELTRO - Configuración del File Server con SSH
################################################################################

set -e

echo "=========================================="
echo "  VELTRO FILE SERVER - INICIANDO"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Instalar paquetes necesarios
log "Instalando paquetes necesarios..."
dnf install -y openssh-server sudo acl rsync \
    procps-ng net-tools lsof telnet nc vim less htop

# 2. Configurar SSH
log "Configurando SSH Server..."
ssh-keygen -A
mkdir -p /var/run/sshd

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

# 3. Crear usuarios
log "Creando usuarios..."
id mlopez &>/dev/null || useradd -m -G wheel mlopez
id fmartinez &>/dev/null || useradd -m fmartinez
id ngalego &>/dev/null || useradd -m ngalego
id mlandaco &>/dev/null || useradd -m mlandaco
id pfumero &>/dev/null || useradd -m pfumero

echo 'mlopez:Admin_V3ltr0_2025!' | chpasswd
echo 'fmartinez:Dev_V3ltr0_2025!' | chpasswd
echo 'ngalego:Dev_V3ltr0_2025!' | chpasswd
echo 'mlandaco:Dev_V3ltr0_2025!' | chpasswd
echo 'pfumero:Test_V3ltr0_2025!' | chpasswd

# 4. Crear grupos
groupadd admins 2>/dev/null && usermod -aG admins mlopez
groupadd developers 2>/dev/null && usermod -aG developers fmartinez ngalego mlandaco
groupadd testers 2>/dev/null && usermod -aG testers pfumero

# 5. Crear estructura de directorios
log "Creando estructura de directorios..."
mkdir -p /srv/shared/{admin,devs,testers,common,logs,projects}

# 6. Configurar permisos
chown -R mlopez:admins /srv/shared/admin
chown -R root:developers /srv/shared/devs
chown -R pfumero:testers /srv/shared/testers
chown -R root:root /srv/shared/common

chmod 2770 /srv/shared/admin
chmod 2770 /srv/shared/devs
chmod 2770 /srv/shared/testers
chmod 2775 /srv/shared/common

# 7. Configurar ACL
setfacl -R -m g:admins:rwx /srv/shared/admin 2>/dev/null || true
setfacl -R -m g:developers:rwx /srv/shared/devs 2>/dev/null || true
setfacl -R -m g:testers:rwx /srv/shared/testers 2>/dev/null || true
setfacl -R -d -m g:admins:rwx /srv/shared/admin 2>/dev/null || true
setfacl -R -d -m g:developers:rwx /srv/shared/devs 2>/dev/null || true
setfacl -R -d -m g:testers:rwx /srv/shared/testers 2>/dev/null || true

# 8. Crear archivo README
echo "Veltro Enterprise File Server - Fedora" > /srv/shared/common/README.txt

# 9. Iniciar SSH
log "Iniciando SSH..."
/usr/sbin/sshd

# Mantener el contenedor vivo
tail -f /dev/null