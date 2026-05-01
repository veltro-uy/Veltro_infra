#!/bin/bash
################################################################################
# VELTRO - Configuración del File Server
################################################################################

set -e

echo "=========================================="
echo "  VELTRO FILE SERVER - INICIANDO"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Instalar paquetes
log "Instalando paquetes..."
dnf install -y openssh-server sudo rsync telnet nc procps-ng net-tools

# 2. Configurar SSH
log "Configurando SSH..."
ssh-keygen -A
mkdir -p /var/run/sshd

cat > /etc/ssh/sshd_config <<'EOF'
Port 22
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd no
Subsystem sftp /usr/libexec/openssh/sftp-server
EOF

# 3. Crear grupos
log "Creando grupos..."
groupadd admins 2>/dev/null || true
groupadd developers 2>/dev/null || true
groupadd testers 2>/dev/null || true

# 4. Crear usuarios
log "Creando usuarios..."

# Usuario Administrador
if ! id mlopez &>/dev/null; then
    useradd -m -G wheel,admins mlopez
fi
echo 'mlopez:Admin_V3ltr0_2025!' | chpasswd
log "✓ Usuario mlopez (Administrador) creado"

# Usuario Desarrollador 1
if ! id fmartinez &>/dev/null; then
    useradd -m -G developers fmartinez
fi
echo 'fmartinez:Dev_V3ltr0_2025!' | chpasswd
log "✓ Usuario fmartinez (Desarrollador) creado"

# Usuario Desarrollador 2
if ! id ngalego &>/dev/null; then
    useradd -m -G developers ngalego
fi
echo 'ngalego:Dev_V3ltr0_2025!' | chpasswd
log "✓ Usuario ngalego (Desarrollador) creado"

# Usuario Desarrollador 3
if ! id mlandaco &>/dev/null; then
    useradd -m -G developers mlandaco
fi
echo 'mlandaco:Dev_V3ltr0_2025!' | chpasswd
log "✓ Usuario mlandaco (Desarrollador) creado"

# Usuario Tester
if ! id pfumero &>/dev/null; then
    useradd -m -G testers pfumero
fi
echo 'pfumero:Test_V3ltr0_2025!' | chpasswd
log "✓ Usuario pfumero (Tester) creado"

# 5. Crear estructura de directorios
log "Creando directorios compartidos..."
mkdir -p /srv/shared/{admin,devs,testers,common,logs,projects}

# 6. CONFIGURAR PERMISOS (sin ACL)
log "Configurando permisos..."

# Admin - solo mlopez puede escribir
chown -R mlopez:admins /srv/shared/admin
chmod 750 /srv/shared/admin

# Devs - desarrolladores pueden escribir, admins pueden leer
chown -R root:developers /srv/shared/devs
chmod 750 /srv/shared/devs
usermod -aG developers mlopez  # mlopez también en developers para lectura

# Testers - testers pueden escribir, admins pueden leer
chown -R pfumero:testers /srv/shared/testers
chmod 750 /srv/shared/testers
usermod -aG testers mlopez  # mlopez también en testers para lectura

# Projects - desarrolladores pueden escribir, admins pueden leer
chown -R root:developers /srv/shared/projects
chmod 750 /srv/shared/projects

# Common - todos pueden leer
chown -R root:root /srv/shared/common
chmod 755 /srv/shared/common

# Logs - solo admins
chown -R mlopez:admins /srv/shared/logs
chmod 750 /srv/shared/logs

log "✓ Permisos configurados"

# 7. Crear archivos de información
log "Creando archivos de información..."
echo "Veltro Enterprise File Server" > /srv/shared/common/README.txt
echo "" >> /srv/shared/common/README.txt
echo "Usuarios:" >> /srv/shared/common/README.txt
echo "  - mlopez (Administrador) / Admin_V3ltr0_2025!" >> /srv/shared/common/README.txt
echo "  - fmartinez (Desarrollador) / Dev_V3ltr0_2025!" >> /srv/shared/common/README.txt
echo "  - ngalego (Desarrollador) / Dev_V3ltr0_2025!" >> /srv/shared/common/README.txt
echo "  - mlandaco (Desarrollador) / Dev_V3ltr0_2025!" >> /srv/shared/common/README.txt
echo "  - pfumero (Tester) / Test_V3ltr0_2025!" >> /srv/shared/common/README.txt

# 8. Crear directorios .ssh y configurar acceso
log "Configurando directorios .ssh..."
for user in mlopez fmartinez ngalego mlandaco pfumero; do
    mkdir -p /home/$user/.ssh
    chmod 700 /home/$user/.ssh
    touch /home/$user/.ssh/authorized_keys
    chmod 600 /home/$user/.ssh/authorized_keys
    chown -R $user:$user /home/$user/.ssh
done

# 9. Iniciar SSH
log "Iniciando SSH..."
/usr/sbin/sshd

# 10. Verificar
if pgrep -x sshd > /dev/null; then
    log "✓ SSH corriendo correctamente"
else
    log "⚠ ERROR: SSH no pudo iniciarse"
fi

# 11. Mantener el contenedor vivo
log "File Server listo. Manteniendo servicios activos..."
while true; do
    if ! pgrep -x sshd > /dev/null; then
        log "SSH caído, reiniciando..."
        /usr/sbin/sshd
    fi
    sleep 30
done