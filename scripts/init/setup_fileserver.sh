#!/bin/bash
################################################################################
# VELTRO - Configuración del File Server (Sin Samba)
# Ejecutado automáticamente al levantar el contenedor
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
PasswordAuthentication no
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

for user in mlopez fmartinez ngalego mlandaco pfumero; do
    if ! id $user &>/dev/null; then
        useradd -m $user
        log "  Usuario $user creado"
    fi
done

# Asignar grupos
usermod -aG wheel,admins mlopez 2>/dev/null || true
usermod -aG developers fmartinez 2>/dev/null || true
usermod -aG developers ngalego 2>/dev/null || true
usermod -aG developers mlandaco 2>/dev/null || true
usermod -aG testers pfumero 2>/dev/null || true

# Establecer contraseñas
echo 'mlopez:Admin_V3ltr0_2025!' | chpasswd 2>/dev/null || true
echo 'fmartinez:Dev_V3ltr0_2025!' | chpasswd 2>/dev/null || true
echo 'ngalego:Dev_V3ltr0_2025!' | chpasswd 2>/dev/null || true
echo 'mlandaco:Dev_V3ltr0_2025!' | chpasswd 2>/dev/null || true
echo 'pfumero:Test_V3ltr0_2025!' | chpasswd 2>/dev/null || true

log "✓ Usuarios configurados"

# 5. Crear usuario backup (SOLO para backups)
log "Creando usuario backup..."
if ! id backup &>/dev/null; then
    useradd -m -s /bin/bash backup
    echo 'backup:B4ckup_V3ltr0_2025!' | chpasswd
    log "  Usuario backup creado"
else
    log "  Usuario backup ya existe"
fi

# 6. Directorios
log "Creando directorios..."
mkdir -p /srv/shared/{admin,devs,testers,common,logs,projects}

# 7. Permisos
log "Configurando permisos..."

# Propietarios
chown -R mlopez:admins /srv/shared/admin 2>/dev/null || true
chown -R root:developers /srv/shared/devs 2>/dev/null || true
chown -R pfumero:testers /srv/shared/testers 2>/dev/null || true
chown -R root:root /srv/shared/common 2>/dev/null || true
chown -R mlopez:admins /srv/shared/logs 2>/dev/null || true
chown -R root:developers /srv/shared/projects 2>/dev/null || true

chmod 2770 /srv/shared/admin 2>/dev/null || true
chmod 2770 /srv/shared/devs 2>/dev/null || true
chmod 2770 /srv/shared/testers 2>/dev/null || true
chmod 2775 /srv/shared/common 2>/dev/null || true
chmod 2770 /srv/shared/logs 2>/dev/null || true
chmod 2770 /srv/shared/projects 2>/dev/null || true

# ⭐ Dar permisos de LECTURA al usuario backup en TODO
log "Dando permisos de lectura a backup en /srv/shared..."
usermod -aG admins,developers,testers backup 2>/dev/null || true
chmod -R 755 /srv/shared 2>/dev/null || true

log "✓ Permisos aplicados"

# 8. ⭐ Crear directorio .ssh para todos los usuarios (preparado para la clave)
log "Preparando directorios .ssh para todos los usuarios..."
for user in backup mlopez fmartinez ngalego mlandaco pfumero; do
    mkdir -p /home/$user/.ssh
    chmod 700 /home/$user/.ssh
    chown -R $user:$user /home/$user/.ssh
done
log "✓ Directorios .ssh preparados"

# 9. Iniciar servicios
log "Iniciando servicios..."
/usr/sbin/sshd

log "✓ Servicios iniciados"

# 10. Mantener vivo
log "File Server listo. Manteniendo servicios activos..."
while true; do
    if ! pgrep -x sshd > /dev/null; then
        /usr/sbin/sshd
    fi
    sleep 30
done