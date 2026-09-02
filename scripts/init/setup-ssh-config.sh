#!/bin/bash
################################################################################
# VELTRO - Instalación de clave SSH del Backup Server en el File Server
#
# Se ejecuta automáticamente después de 'docker-compose up -d' (ver
# start-veltro.sh). Usa 'docker exec' para copiar la clave, NO SSH,
# así que no depende de PasswordAuthentication ni de que ambos
# contenedores compartan red/DNS de Docker.
################################################################################

set -u

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

echo "=== VELTRO - Instalando clave SSH en File Server ==="

MAX_RETRIES=30
SLEEP_SECONDS=2

# 1. Esperar a que el contenedor del Backup Server esté corriendo
log "Esperando a que svveltrobackup esté corriendo..."
for i in $(seq 1 $MAX_RETRIES); do
    if [ "$(docker inspect -f '{{.State.Running}}' svveltrobackup 2>/dev/null)" = "true" ]; then
        log "✅ svveltrobackup está corriendo"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "❌ Timeout esperando a que svveltrobackup esté corriendo"
        exit 1
    fi
    sleep $SLEEP_SECONDS
done

# 2. Esperar a que la clave pública exista dentro del contenedor
log "Esperando a que la clave SSH exista en Backup Server..."
PUB_KEY=""
for i in $(seq 1 $MAX_RETRIES); do
    PUB_KEY=$(docker exec svveltrobackup cat /home/backup/.ssh/id_rsa.pub 2>/dev/null)
    if [ -n "$PUB_KEY" ]; then
        log "✅ Clave encontrada en Backup Server"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "❌ Clave no encontrada en Backup Server tras esperar $((MAX_RETRIES * SLEEP_SECONDS))s"
        echo "   Verificá manualmente con: docker logs svveltrobackup"
        exit 1
    fi
    sleep $SLEEP_SECONDS
done

# 3. Esperar a que el contenedor del File Server esté corriendo
log "Esperando a que fileserver esté corriendo..."
for i in $(seq 1 $MAX_RETRIES); do
    if [ "$(docker inspect -f '{{.State.Running}}' fileserver 2>/dev/null)" = "true" ]; then
        log "✅ fileserver está corriendo"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "❌ Timeout esperando a que fileserver esté corriendo"
        exit 1
    fi
    sleep $SLEEP_SECONDS
done

# 4. Esperar a que los usuarios y directorios .ssh ya existan en el File Server
#    (los crea setup_fileserver.sh en su paso 8; si intentamos escribir antes,
#    'mkdir -p' de abajo lo cubre igual, pero esperamos por prolijidad)
log "Esperando a que el usuario mlopez exista en File Server..."
for i in $(seq 1 $MAX_RETRIES); do
    if docker exec fileserver id mlopez &>/dev/null; then
        log "✅ Usuarios listos en File Server"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "❌ Timeout esperando a que los usuarios existan en File Server"
        exit 1
    fi
    sleep $SLEEP_SECONDS
done

# 5. Instalar la clave para todos los usuarios (vía docker exec, sin SSH)
log "Instalando clave en File Server..."
docker exec fileserver /bin/bash -c "
    for user in backup mlopez fmartinez ngalego mlandaco pfumero; do
        mkdir -p /home/\$user/.ssh
        chmod 700 /home/\$user/.ssh
        echo '$PUB_KEY' > /home/\$user/.ssh/authorized_keys
        chmod 600 /home/\$user/.ssh/authorized_keys
        chown -R \$user:\$user /home/\$user/.ssh
    done
"

if [ $? -eq 0 ]; then
    log "✅ Clave instalada para todos los usuarios"
else
    echo "❌ Falló la instalación de la clave en File Server"
    exit 1
fi

# 6. Copiar clave privada al host (opcional, útil para debug manual desde el host)
log "Copiando clave al host..."
mkdir -p ~/.ssh
docker cp svveltrobackup:/home/backup/.ssh/id_rsa ~/.ssh/id_rsa_backup 2>/dev/null
docker cp svveltrobackup:/home/backup/.ssh/id_rsa.pub ~/.ssh/id_rsa_backup.pub 2>/dev/null
chmod 600 ~/.ssh/id_rsa_backup 2>/dev/null
chmod 644 ~/.ssh/id_rsa_backup.pub 2>/dev/null
log "✅ Clave copiada al host"

# 7. Agregar known_hosts dentro del Backup Server (SOLO por IP)
#    NOTA: se quitó 'ssh-keyscan -H fileserver' porque svveltrobackup
#    (dmz_network) no comparte red Docker con fileserver (lan_network +
#    VLANs), por lo que el nombre 'fileserver' no resuelve por DNS interno
#    de Docker aunque la IP sí sea alcanzable por routing. Intentar
#    resolverlo por hostname fallaba siempre y, si este bloque se hubiera
#    dejado dentro de un script con 'set -e', tumbaba el contenedor.
log "Agregando known_hosts (por IP)..."
docker exec svveltrobackup /bin/bash -c "
    ssh-keyscan -H 192.168.0.100 >> /home/backup/.ssh/known_hosts 2>/dev/null
"
log "✅ known_hosts actualizado"

# 8. Verificación final: probar la conexión SSH real backup -> fileserver
log "Verificando conexión SSH backup -> fileserver..."
if docker exec -u backup svveltrobackup ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 backup@192.168.0.100 "echo OK" 2>/dev/null | grep -q OK; then
    log "✅ Conexión SSH verificada correctamente"
else
    echo "⚠ No se pudo verificar la conexión SSH (puede que el sshd del File Server aún esté iniciando)."
    echo "   Probá manualmente: docker exec -u backup svveltrobackup ssh backup@192.168.0.100 echo OK"
fi

echo "=== CONFIGURACIÓN COMPLETADA ==="
