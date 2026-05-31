#!/bin/bash
################################################################################
# VELTRO - Configuración del File Server con Samba
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
dnf install -y openssh-server sudo acl rsync telnet nc procps-ng net-tools samba samba-client

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
groupadd sambashare 2>/dev/null || true

# 4. Crear usuarios
log "Creando usuarios..."

for user in mlopez fmartinez ngalego mlandaco pfumero; do
    if ! id $user &>/dev/null; then
        useradd -m $user
        log "  Usuario $user creado"
    fi
done

# Asignar grupos
usermod -aG wheel,admins,sambashare mlopez
usermod -aG developers,sambashare fmartinez
usermod -aG developers,sambashare ngalego
usermod -aG developers,sambashare mlandaco
usermod -aG testers,sambashare pfumero

# Establecer contraseñas
echo 'mlopez:Admin_V3ltr0_2025!' | chpasswd
echo 'fmartinez:Dev_V3ltr0_2025!' | chpasswd
echo 'ngalego:Dev_V3ltr0_2025!' | chpasswd
echo 'mlandaco:Dev_V3ltr0_2025!' | chpasswd
echo 'pfumero:Test_V3ltr0_2025!' | chpasswd

log "✓ Usuarios configurados"

# 5. Directorios
log "Creando directorios..."
mkdir -p /srv/shared/{admin,devs,testers,common,logs,projects}

chown -R mlopez:admins /srv/shared/admin
chown -R root:developers /srv/shared/devs
chown -R pfumero:testers /srv/shared/testers
chown -R root:root /srv/shared/common
chown -R mlopez:admins /srv/shared/logs
chown -R root:developers /srv/shared/projects

chmod 2770 /srv/shared/admin
chmod 2770 /srv/shared/devs
chmod 2770 /srv/shared/testers
chmod 2775 /srv/shared/common
chmod 2770 /srv/shared/logs
chmod 2770 /srv/shared/projects

# 6. Configurar Samba
log "Configurando Samba..."

cat > /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = VELTRO
   server string = VELTRO File Server
   netbios name = FILESERVER
   security = user
   map to guest = Bad User
   passdb backend = tdbsam

[admin]
   path = /srv/shared/admin
   valid users = @admins
   admin users = mlopez
   read only = no
   browsable = yes
   create mask = 0660
   directory mask = 0770

[devs]
   path = /srv/shared/devs
   valid users = @developers
   read only = no
   browsable = yes
   create mask = 0660
   directory mask = 0770

[testers]
   path = /srv/shared/testers
   valid users = @testers
   read only = no
   browsable = yes
   create mask = 0660
   directory mask = 0770

[common]
   path = /srv/shared/common
   valid users = @admins,@developers,@testers
   read only = yes
   browsable = yes

[projects]
   path = /srv/shared/projects
   valid users = @developers,@admins
   read only = no
   browsable = yes
   create mask = 0660
   directory mask = 0770
EOF

# Contraseñas Samba
(echo "Admin_V3ltr0_2025!"; echo "Admin_V3ltr0_2025!") | smbpasswd -a mlopez -s
(echo "Dev_V3ltr0_2025!"; echo "Dev_V3ltr0_2025!") | smbpasswd -a fmartinez -s
(echo "Dev_V3ltr0_2025!"; echo "Dev_V3ltr0_2025!") | smbpasswd -a ngalego -s
(echo "Dev_V3ltr0_2025!"; echo "Dev_V3ltr0_2025!") | smbpasswd -a mlandaco -s
(echo "Test_V3ltr0_2025!"; echo "Test_V3ltr0_2025!") | smbpasswd -a pfumero -s

log "✓ Samba configurado"

# 7. Iniciar servicios
log "Iniciando servicios..."
/usr/sbin/sshd
smbd -D
nmbd -D

log "✓ Servicios iniciados"

# 8. Mantener vivo
log "File Server listo. Manteniendo servicios activos..."
while true; do
    if ! pgrep -x sshd > /dev/null; then
        /usr/sbin/sshd
    fi
    if ! pgrep -x smbd > /dev/null; then
        smbd -D
    fi
    sleep 30
done