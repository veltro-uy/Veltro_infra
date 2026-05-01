#!/bin/bash
################################################################################
# VELTRO - Configura acceso SSH automático del Backup Server al File Server
# Este script se ejecuta DESPUÉS de que ambos servidores estén listos
################################################################################

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "=========================================="
log "  Configurando acceso SSH al File Server"
log "=========================================="

# Variables
FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
FILESERVER_PASS="Admin_V3ltr0_2025!"

# Esperar a que el File Server esté disponible
log "Esperando a que el File Server ($FILESERVER_IP) esté disponible..."
while ! nc -z $FILESERVER_IP 22 2>/dev/null; do
    sleep 2
done
sleep 10  # Esperar adicional para que SSH esté listo
log "✓ File Server disponible"

# Copiar clave pública al File Server
log "Copiando clave SSH al File Server..."
PUB_KEY=$(cat /root/.ssh/id_rsa.pub)
ssh -p 22 $FILESERVER_USER@$FILESERVER_IP "mkdir -p /home/$FILESERVER_USER/.ssh && chmod 700 /home/$FILESERVER_USER/.ssh && echo '$PUB_KEY' >> /home/$FILESERVER_USER/.ssh/authorized_keys && chmod 600 /home/$FILESERVER_USER/.ssh/authorized_keys && chown -R $FILESERVER_USER:$FILESERVER_USER /home/$FILESERVER_USER/.ssh" 2>/dev/null

# Probar conexión
log "Probando conexión SSH al File Server..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes mlopez@$FILESERVER_LAN_IP "echo OK" 2>/dev/null; then
    log "✓ Conexión SSH establecida con mlopez@fileserver ($FILESERVER_LAN_IP)"
else
    log "⚠ No se pudo establecer conexión SSH automática"
fi

log "=========================================="
log "  Configuración SSH completada"
log "=========================================="