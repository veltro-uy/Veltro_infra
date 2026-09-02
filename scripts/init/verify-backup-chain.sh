#!/bin/bash
################################################################################
# VELTRO - Verificación de la cadena de Backup
#
# Uso manual y opcional. NO se ejecuta automáticamente al levantar Docker.
#
#   ./scripts/init/verify-backup-chain.sh
#
# Verifica, de punta a punta, que un backup real podría ejecutarse ahora
# mismo sin fallar: contenedor corriendo, clave SSH instalada, known_hosts,
# conexión SSH real al Fileserver, acceso a MySQL Master, y una prueba de
# transferencia (tar sobre SSH) igual a la que usa backup_fileserver.sh,
# pero descartando el resultado (no escribe nada en /backup).
#
# Código de salida: 0 si todo OK, 1 si algo falló.
################################################################################

set -u

FILESERVER_IP="192.168.0.100"
FILESERVER_USER="mlopez"
MYSQL_MASTER_IP="192.168.20.20"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
info() { echo "  ℹ️  $1"; }

echo "=========================================="
echo "  VELTRO - Verificación de cadena de Backup"
echo "  $(date)"
echo "=========================================="

# ------------------------------------------------------------------
echo ""
echo "[1/6] Contenedores"
# ------------------------------------------------------------------
if [ "$(docker inspect -f '{{.State.Running}}' svveltrobackup 2>/dev/null)" = "true" ]; then
    ok "svveltrobackup está corriendo"
else
    bad "svveltrobackup no está corriendo (docker-compose up -d)"
fi

if [ "$(docker inspect -f '{{.State.Running}}' fileserver 2>/dev/null)" = "true" ]; then
    ok "fileserver está corriendo"
else
    bad "fileserver no está corriendo (docker-compose up -d)"
fi

if [ "$(docker inspect -f '{{.State.Running}}' svveltrobdm 2>/dev/null)" = "true" ]; then
    ok "svveltrobdm (MySQL Master) está corriendo"
else
    bad "svveltrobdm no está corriendo"
fi

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "⚠ Algún contenedor no está corriendo. El resto de los chequeos puede fallar en cascada."
fi

# ------------------------------------------------------------------
echo ""
echo "[2/6] Clave SSH del Backup Server"
# ------------------------------------------------------------------
PUB_KEY=$(docker exec svveltrobackup cat /home/backup/.ssh/id_rsa.pub 2>/dev/null)
if [ -n "$PUB_KEY" ]; then
    ok "Clave pública existe en svveltrobackup"
else
    bad "No se encontró /home/backup/.ssh/id_rsa.pub en svveltrobackup"
fi

# ------------------------------------------------------------------
echo ""
echo "[3/6] Clave instalada en el Fileserver"
# ------------------------------------------------------------------
INSTALLED_KEY=$(docker exec fileserver cat /home/backup/.ssh/authorized_keys 2>/dev/null)
if [ -n "$PUB_KEY" ] && [ "$PUB_KEY" = "$INSTALLED_KEY" ]; then
    ok "authorized_keys de 'backup' en fileserver coincide con la clave del Backup Server"
elif [ -n "$INSTALLED_KEY" ]; then
    bad "authorized_keys de 'backup' en fileserver existe pero NO coincide con la clave actual (¿clave vieja?)"
else
    bad "authorized_keys de 'backup' en fileserver está vacío o no existe"
    info "Corré: ./scripts/init/setup-ssh-config.sh"
fi

# También el usuario mlopez, que es el que usan los scripts de backup
INSTALLED_KEY_MLOPEZ=$(docker exec fileserver cat /home/mlopez/.ssh/authorized_keys 2>/dev/null)
if [ -n "$PUB_KEY" ] && [ "$PUB_KEY" = "$INSTALLED_KEY_MLOPEZ" ]; then
    ok "authorized_keys de 'mlopez' en fileserver coincide con la clave del Backup Server"
else
    bad "authorized_keys de 'mlopez' en fileserver no coincide o no existe (los scripts de backup usan este usuario)"
    info "Corré: ./scripts/init/setup-ssh-config.sh"
fi

# ------------------------------------------------------------------
echo ""
echo "[4/6] Conexión SSH real (backup@svveltrobackup -> mlopez@fileserver)"
# ------------------------------------------------------------------
SSH_TEST=$(docker exec -u backup svveltrobackup ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes \
    "${FILESERVER_USER}@${FILESERVER_IP}" "echo OK" 2>/dev/null)

if [ "$SSH_TEST" = "OK" ]; then
    ok "Conexión SSH funcional a ${FILESERVER_USER}@${FILESERVER_IP}"
else
    bad "No se pudo conectar por SSH a ${FILESERVER_USER}@${FILESERVER_IP}"
    info "Corré manualmente para ver el detalle:"
    info "  docker exec -u backup svveltrobackup ssh ${FILESERVER_USER}@${FILESERVER_IP} echo OK"
fi

# ------------------------------------------------------------------
echo ""
echo "[5/6] Acceso a MySQL Master (necesario para el backup de base de datos)"
# ------------------------------------------------------------------
MYSQL_TEST=$(docker exec svveltrobackup mysql -h "$MYSQL_MASTER_IP" -uroot -pMasterDB_V3ltr0_2025! -e "SELECT 1;" 2>/dev/null)
if echo "$MYSQL_TEST" | grep -q "1"; then
    ok "Conexión a MySQL Master ($MYSQL_MASTER_IP) funcional"
else
    bad "No se pudo conectar a MySQL Master ($MYSQL_MASTER_IP) desde svveltrobackup"
fi

# ------------------------------------------------------------------
echo ""
echo "[6/6] Prueba real de transferencia (igual a backup_fileserver.sh, sin guardar nada)"
# ------------------------------------------------------------------
if [ "$SSH_TEST" = "OK" ]; then
    TRANSFER_TEST=$(docker exec -u backup svveltrobackup bash -c "
        ssh -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes \
            ${FILESERVER_USER}@${FILESERVER_IP} 'tar -czf - -C /srv shared 2>/dev/null' | wc -c
    " 2>/dev/null)

    if [ -n "$TRANSFER_TEST" ] && [ "$TRANSFER_TEST" -gt 0 ] 2>/dev/null; then
        ok "Transferencia de prueba OK (${TRANSFER_TEST} bytes recibidos de /srv/shared)"
    else
        bad "La transferencia de prueba devolvió 0 bytes (el tar.gz mensual saldría vacío)"
    fi
else
    bad "Se omite (depende de que [4/6] haya pasado)"
fi

# ------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  RESULTADO: $PASS OK / $FAIL FALLOS"
echo "=========================================="

if [ "$FAIL" -eq 0 ]; then
    echo "✅ La cadena de backup está sana. Un backup mensual ahora mismo debería funcionar."
    exit 0
else
    echo "❌ Hay $FAIL problema(s). Revisá los puntos marcados con ❌ arriba antes de confiar en el próximo backup automático."
    exit 1
fi
