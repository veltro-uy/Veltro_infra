#!/bin/bash
################################################################################
# VELTRO - Configura acceso SSH automático del Backup Server al File Server
# Este script se ejecuta DESDE EL BACKUP SERVER (como usuario backup)
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "=========================================="
log "  Configurando acceso SSH al File Server"
log "=========================================="

# Variables
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
BACKUP_USER="backup"

# ✅ USAR LA CLAVE DEL USUARIO ACTUAL (backup)
PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"
PUB_KEY=$(cat "$PUB_KEY_PATH" 2>/dev/null)

# Verificar que la clave existe
if [ -z "$PUB_KEY" ]; then
    log "⚠ No se encontró clave SSH en $PUB_KEY_PATH"
    log "Generando nueva clave SSH..."
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" -q
    chmod 600 "$HOME/.ssh/id_rsa"
    chmod 644 "$HOME/.ssh/id_rsa.pub"
    chown -R $(whoami):$(whoami) "$HOME/.ssh"
    PUB_KEY=$(cat "$PUB_KEY_PATH")
    log "✓ Clave SSH generada"
fi

log "✓ Clave pública cargada"

# Esperar a que el File Server esté disponible
log "Esperando a que el File Server ($FILESERVER_IP) esté disponible..."
while ! nc -z $FILESERVER_IP 22 2>/dev/null; do
    sleep 2
done
sleep 3
log "✓ File Server disponible"

# Copiar clave al File Server usando sshpass (primera conexión)
log "Copiando clave SSH al File Server..."

# Instalar sshpass si no está
if ! command -v sshpass &> /dev/null; then
    log "Instalando sshpass..."
    sudo dnf install -y sshpass 2>/dev/null || echo "⚠ No se pudo instalar sshpass"
fi

# Para mlopez
sshpass -p "Admin_V3ltr0_2025!" ssh -o StrictHostKeyChecking=no $FILESERVER_USER@$FILESERVER_IP "
    mkdir -p /home/$FILESERVER_USER/.ssh
    chmod 700 /home/$FILESERVER_USER/.ssh
    echo '$PUB_KEY' >> /home/$FILESERVER_USER/.ssh/authorized_keys
    chmod 600 /home/$FILESERVER_USER/.ssh/authorized_keys
    chown -R $FILESERVER_USER:$FILESERVER_USER /home/$FILESERVER_USER/.ssh
" 2>/dev/null

# Para backup (si no existe, se crea)
sshpass -p "Admin_V3ltr0_2025!" ssh -o StrictHostKeyChecking=no $FILESERVER_USER@$FILESERVER_IP "
    sudo useradd -m -s /bin/bash backup 2>/dev/null || true
    echo 'backup:B4ckup_V3ltr0_2025!' | sudo chpasswd
    sudo mkdir -p /home/backup/.ssh
    sudo chmod 700 /home/backup/.ssh
    echo '$PUB_KEY' | sudo tee /home/backup/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /home/backup/.ssh/authorized_keys
    sudo chown -R backup:backup /home/backup/.ssh
" 2>/dev/null

# Agregar known_hosts
log "Agregando File Server a known_hosts..."
ssh-keyscan -H $FILESERVER_IP >> "$HOME/.ssh/known_hosts" 2>/dev/null
ssh-keyscan -H fileserver >> "$HOME/.ssh/known_hosts" 2>/dev/null
chmod 644 "$HOME/.ssh/known_hosts"

# Probar conexión
log "Probando conexión SSH al File Server..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes $BACKUP_USER@$FILESERVER_IP "echo OK" 2>/dev/null; then
    log "✓ Conexión SSH establecida con $BACKUP_USER@fileserver"
elif ssh -o ConnectTimeout=5 -o BatchMode=yes $FILESERVER_USER@$FILESERVER_IP "echo OK" 2>/dev/null; then
    log "✓ Conexión SSH establecida con $FILESERVER_USER@fileserver"
else
    log "⚠ No se pudo establecer conexión SSH automática"
fi

log "=========================================="
log "  Configuración SSH completada"
log "=========================================="