#!/bin/bash
################################################################################
# VELTRO - Backup del File Server (usando IP directa)
#
# IMPORTANTE: este script debe devolver un código de salida distinto de 0
# si el backup no se pudo realizar. backup_full_monthly.sh usa 'set -e' y
# depende de este código de salida para detectar el fallo; si acá siempre
# devolvemos éxito, el mensual se reporta como "completado" aunque el
# fileserver no se haya respaldado.
################################################################################

FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
DATE=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%Y%m)
BACKUP_DIR="/backup/fileserver/full/$MONTH"
mkdir -p "$BACKUP_DIR"

# Mismas opciones SSH que usa backup_incremental_weekly.sh, para que el
# resultado no dependa de si known_hosts tiene o no la entrada del fileserver
# (evita que un contenedor recién recreado, sin known_hosts poblado, falle
# por verificación de host key en lugar de intentar la conexión).
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"

echo "=== Backup de Fileserver ==="

# Verificar conectividad SSH antes de intentar el backup, para dar un
# mensaje de error claro en vez de un tar.gz vacío sin explicación.
if ! ssh -p 22 $SSH_OPTS "$FILESERVER_USER@$FILESERVER_IP" "echo OK" >/dev/null 2>&1; then
    echo "❌ No se pudo establecer conexión SSH con el Fileserver ($FILESERVER_IP)"
    echo "   Verificá que la clave esté instalada: ./scripts/init/setup-ssh-config.sh"
    exit 1
fi

OUTFILE="$BACKUP_DIR/fileserver_full_${DATE}.tar.gz"

# Capturamos el exit code del ssh (lado remoto) por separado del de la
# escritura local, usando PIPESTATUS, para no depender únicamente de si
# el archivo quedó vacío.
ssh -p 22 $SSH_OPTS "$FILESERVER_USER@$FILESERVER_IP" "tar -czf - -C /srv shared 2>/dev/null" > "$OUTFILE"
SSH_EXIT=${PIPESTATUS[0]}

if [ "$SSH_EXIT" -ne 0 ]; then
    echo "❌ El comando remoto (tar sobre SSH) falló con código $SSH_EXIT"
    rm -f "$OUTFILE"
    exit 1
fi

if [ -s "$OUTFILE" ]; then
    SIZE=$(du -h "$OUTFILE" | cut -f1)
    echo "✓ Backup Fileserver: $SIZE"

    # Mostrar contenido del backup
    echo "  Contenido:"
    tar -tzf "$OUTFILE" 2>/dev/null | head -10 | sed 's/^/    /'

    md5sum "$OUTFILE" > "${OUTFILE}.md5"
    exit 0
else
    echo "❌ No se pudo crear el backup del Fileserver (archivo vacío)"
    rm -f "$OUTFILE"
    exit 1
fi
