#!/bin/bash
################################################################################
# VELTRO - Configuración automática de replicación Master-Slave
################################################################################

set -e

echo "=========================================="
echo "  VELTRO - Configurando replicación"
echo "=========================================="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 1. Esperar a que MySQL Slave esté listo
log "Esperando a que MySQL Slave esté listo..."
until mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT 1" >/dev/null 2>&1; do
    sleep 2
done
log "✓ MySQL Slave listo"

# 2. Verificar si la replicación ya está configurada
SLAVE_STATUS=$(mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW SLAVE STATUS\G" 2>/dev/null)
if echo "$SLAVE_STATUS" | grep -q "Slave_IO_Running: Yes"; then
    log "✓ Replicación ya está configurada y activa"
    exit 0
fi

# 3. Esperar a que el Master esté disponible
log "Esperando a que el Master esté disponible..."
RETRIES=0
MAX_RETRIES=30
while ! mysql -h svveltrobdm -uroot -pMasterDB_V3ltr0_2025! -e "SELECT 1" >/dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        log "ERROR: Master no disponible después de $MAX_RETRIES intentos"
        exit 1
    fi
    log "  Aguardando Master... (intento $RETRIES/$MAX_RETRIES)"
    sleep 5
done
log "✓ Master disponible"

# 4. Verificar que el usuario replicator existe
log "Verificando usuario replicator en Master..."
mysql -h svveltrobdm -uroot -pMasterDB_V3ltr0_2025! -e "
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'Replicator_V3ltr0_2025!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
" 2>/dev/null
log "✓ Usuario replicator verificado"

# 5. Crear usuario exporter en Slave
log "Creando usuario exporter en Slave..."
mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED WITH mysql_native_password BY 'Exp0rt3r_2025!';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
EOF
log "✓ Usuario exporter creado en Slave"

# 6. COPIAR ESTRUCTURA Y DATOS DEL MASTER AL SLAVE
log "Copiando estructura y datos del Master al Slave..."

# Eliminar base de datos existente en Slave si existe
mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "DROP DATABASE IF EXISTS veltro_prod;" 2>/dev/null

# Crear base de datos vacía
mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE veltro_prod;" 2>/dev/null

# Copiar estructura y datos usando pipe
mysqldump -h svveltrobdm -uroot -pMasterDB_V3ltr0_2025! \
    --single-transaction \
    --set-gtid-purged=OFF \
    veltro_prod 2>/dev/null | mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} veltro_prod 2>/dev/null

log "✓ Datos copiados exitosamente"

# 7. Verificar que los datos se copiaron
TABLE_COUNT=$(mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='veltro_prod' AND table_name='equipos';" -N 2>/dev/null)
if [ "$TABLE_COUNT" -eq "1" ]; then
    RECORD_COUNT=$(mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT COUNT(*) FROM veltro_prod.equipos;" -N 2>/dev/null)
    log "✓ Tablas creadas correctamente. Registros en equipos: $RECORD_COUNT"
else
    log "ERROR: No se pudieron copiar los datos"
    exit 1
fi

# 8. Obtener posición del Master
log "Obteniendo posición del Master..."
MASTER_STATUS=$(mysql -h svveltrobdm -ureplicator -pReplicator_V3ltr0_2025! -e "SHOW MASTER STATUS\G" 2>/dev/null)
MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

if [ -z "$MASTER_LOG_FILE" ] || [ -z "$MASTER_LOG_POS" ]; then
    log "ERROR: No se pudo obtener posición del Master"
    exit 1
fi

log "  Master Log File: $MASTER_LOG_FILE"
log "  Master Log Position: $MASTER_LOG_POS"

# 9. Configurar replicación
log "Configurando Slave..."
mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} <<EOF
CHANGE MASTER TO
    MASTER_HOST = 'svveltrobdm',
    MASTER_PORT = 3306,
    MASTER_USER = 'replicator',
    MASTER_PASSWORD = 'Replicator_V3ltr0_2025!',
    MASTER_LOG_FILE = '${MASTER_LOG_FILE}',
    MASTER_LOG_POS = ${MASTER_LOG_POS},
    MASTER_CONNECT_RETRY = 10;
START SLAVE;
EOF

# 10. Verificar estado
sleep 5
SLAVE_STATUS=$(mysql -h localhost -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW SLAVE STATUS\G" 2>/dev/null)
IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')

if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
    log "✅ REPLICACIÓN CONFIGURADA EXITOSAMENTE"
    log "   Slave_IO_Running: $IO_RUNNING"
    log "   Slave_SQL_Running: $SQL_RUNNING"
else
    log "❌ ERROR: No se pudo configurar replicación"
    log "   Slave_IO_Running: $IO_RUNNING"
    log "   Slave_SQL_Running: $SQL_RUNNING"
    exit 1
fi

echo "=========================================="
echo "  REPLICACIÓN CONFIGURADA - FIN"
echo "=========================================="