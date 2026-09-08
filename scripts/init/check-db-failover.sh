#!/bin/bash
################################################################################
# VELTRO - Detección de caída del Master (MySQL) y guía de promoción manual
#
# Uso manual, para diagnóstico ante una alerta de Prometheus/HAProxy o
# sospecha de caída del Master. Cruza el estado que reporta HAProxy con una
# verificación directa al Master (bypass de HAProxy) para evitar falsos
# positivos, y revisa el retraso de replicación del Slave.
#
# Este script NO promueve nada automáticamente. Si confirma la caída,
# imprime los comandos exactos a ejecutar para promover el Slave a mano.
#
#   ./scripts/init/check-db-failover.sh
#
# Código de salida:
#   0 = Master sano, no hay que hacer nada
#   1 = Master caído (confirmado) - requiere decisión de promoción manual
#   2 = Estado inconsistente / advertencia - revisar antes de actuar
################################################################################

set -u

MASTER_IP="192.168.20.20"
MASTER_ROOT_PASS="MasterDB_V3ltr0_2025!"
SLAVE_ROOT_PASS="SlaveDB_V3ltr0_2025!"
HAPROXY_STATS_URL="http://admin:admin@localhost:8404/stats;csv"

ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; }
warn() { echo "  ⚠️  $1"; }
info() { echo "  ℹ️  $1"; }

echo "=========================================="
echo "  VELTRO - Detección de falla del Master"
echo "  $(date)"
echo "=========================================="

# ------------------------------------------------------------------
echo ""
echo "[1/4] Estado reportado por HAProxy (healthcheck automático)"
# ------------------------------------------------------------------
HAPROXY_CSV=$(curl -s --max-time 5 "$HAPROXY_STATS_URL" 2>/dev/null)
MASTER_ROW=$(echo "$HAPROXY_CSV" | grep "^mysql_master,master,")

if [ -z "$MASTER_ROW" ]; then
    warn "No se pudo leer el stats de HAProxy (¿sqlproxy está corriendo? ¿stats habilitado?)"
    HAPROXY_SAYS_DOWN="unknown"
else
    HAPROXY_STATUS=$(echo "$MASTER_ROW" | cut -d',' -f18)
    info "HAProxy reporta el backend 'master' como: $HAPROXY_STATUS"
    if [ "$HAPROXY_STATUS" = "DOWN" ]; then
        HAPROXY_SAYS_DOWN="yes"
    else
        HAPROXY_SAYS_DOWN="no"
    fi
fi

# ------------------------------------------------------------------
echo ""
echo "[2/4] Verificación directa al Master (bypass de HAProxy, 3 intentos)"
# ------------------------------------------------------------------
MASTER_REACHABLE="no"
for i in 1 2 3; do
    if docker exec svveltrobackup mysql -h "$MASTER_IP" -uroot -p"${MASTER_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
        MASTER_REACHABLE="yes"
        break
    fi
    sleep 3
done

if [ "$MASTER_REACHABLE" = "yes" ]; then
    ok "El Master respondió directamente ($MASTER_IP) - está vivo"
else
    bad "El Master NO respondió en 3 intentos ($MASTER_IP)"
fi

# ------------------------------------------------------------------
echo ""
echo "[3/4] Estado del Slave y retraso de replicación"
# ------------------------------------------------------------------
SLAVE_STATUS=$(docker exec svveltrobds mysql -uroot -p"${SLAVE_ROOT_PASS}" -e "SHOW SLAVE STATUS\G" 2>/dev/null)
IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
LAG=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')

if [ -z "$SLAVE_STATUS" ]; then
    bad "No se pudo consultar el Slave (svveltrobds) - ¿está corriendo?"
else
    info "Slave_IO_Running: ${IO_RUNNING:-desconocido} / Slave_SQL_Running: ${SQL_RUNNING:-desconocido}"
    if [ -z "$LAG" ] || [ "$LAG" = "NULL" ]; then
        warn "No se pudo determinar el retraso de replicación (Seconds_Behind_Master = NULL)"
    elif [ "$LAG" -gt 30 ] 2>/dev/null; then
        warn "El Slave tiene ${LAG}s de retraso - si promovés ahora podrías perder las últimas transacciones"
    else
        ok "Retraso de replicación: ${LAG}s"
    fi
fi

# ------------------------------------------------------------------
echo ""
echo "[4/4] Diagnóstico"
# ------------------------------------------------------------------
if [ "$MASTER_REACHABLE" = "yes" ]; then
    echo "✅ El Master está sano. No se requiere ninguna acción."
    exit 0
fi

if [ "$HAPROXY_SAYS_DOWN" = "no" ]; then
    echo "⚠️  INCONSISTENCIA: la verificación directa falló pero HAProxy no marca"
    echo "    el Master como DOWN. Puede ser un problema puntual de red hacia"
    echo "    este host en particular. NO promuevas todavía - reintentá en"
    echo "    unos segundos y confirmá desde otra máquina si es posible."
    exit 2
fi

echo "❌ CAÍDA CONFIRMADA: el Master no respondió a la verificación directa"
echo "   $([ "$HAPROXY_SAYS_DOWN" = "yes" ] && echo "y HAProxy también lo marca como DOWN." || echo "(no se pudo cruzar con el estado de HAProxy).")"
echo ""
echo "-----------------------------------------------------------------"
echo " ESTO NO PROMUEVE NADA AUTOMÁTICAMENTE."
echo " Antes de seguir, evaluá el riesgo de split-brain: si el Master en"
echo " realidad sigue vivo y solo hay un corte de red parcial, promover"
echo " el Slave ahora puede dejar DOS nodos aceptando escrituras a la vez."
echo " Si decidís promover, hacelo en este orden:"
echo "-----------------------------------------------------------------"
echo ""
echo " 1) Confirmá una vez más, desde otro punto de la red si es posible,"
echo "    que el Master realmente está caído (y no accesible por otra vía):"
echo "    docker exec svveltrobdm mysqladmin ping -uroot -p'${MASTER_ROOT_PASS}'"
echo ""
echo " 2) En el Slave, cortá la replicación y sacalo de solo-lectura:"
echo "    docker exec svveltrobds mysql -uroot -p'${SLAVE_ROOT_PASS}' -e \\"
echo "      \"STOP SLAVE; RESET SLAVE ALL; SET GLOBAL read_only = OFF; SET GLOBAL super_read_only = OFF;\""
echo ""
echo " 3) Editá config/haproxy/haproxy.cfg: en el listener 'mysql_master',"
echo "    cambiá 'server master 192.168.20.20:3306 ...' por"
echo "    'server master 192.168.20.40:3306 ...' (la IP del ex-Slave)."
echo ""
echo " 4) Aplicá el cambio. Esta imagen de HAProxy no corre en modo"
echo "    master-worker, así que no hay reload en caliente: hay un corte"
echo "    breve de las conexiones activas al aplicar el cambio."
echo "    docker-compose restart sqlproxy"
echo ""
echo " 5) Cuando el viejo Master vuelva a estar disponible, NO lo dejes"
echo "    reincorporarse solo (puede seguir aceptando escrituras si algo"
echo "    le llega directo, sin pasar por HAProxy). Hay que reconstruirlo"
echo "    como Slave del nuevo Master: mismo procedimiento que"
echo "    scripts/init/setup_replication_on_slave.sh (mysqldump del nuevo"
echo "    Master -> restore -> CHANGE MASTER TO apuntando al nuevo Master)."
echo ""
exit 1
