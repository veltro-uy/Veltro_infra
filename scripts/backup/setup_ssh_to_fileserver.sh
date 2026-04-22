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

# Esperar a que el File Server esté disponible
FILESERVER_LAN_IP="192.168.0.100"
log "Esperando a que el File Server ($FILESERVER_LAN_IP) esté disponible..."
while ! nc -z $FILESERVER_LAN_IP 22 2>/dev/null; do
    sleep 2
done
log "✓ File Server disponible"

# Copiar clave pública al File Server
log "Copiando clave SSH al File Server..."
sshpass -p "Admin_V3ltr0_2025!" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub mlopez@$FILESERVER_LAN_IP 2>/dev/null

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