#!/bin/bash
# test_replication.sh - Prueba continua de replicaci?n

echo "=== PRUEBA CONTINUA DE REPLICACION ==="
echo "Presiona Ctrl+C para detener"
echo ""

COUNT=1
while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Crear datos en Master
    docker exec svveltrobdm mysql -uroot -pMasterDB_V3ltr0_2025! -e "
        INSERT INTO veltro_prod.equipos (nombre, color, estado) 
        VALUES ('Test_$COUNT', '#888888', 'activo');
    " 2>/dev/null
    
    # Verificar en Slave
    RESULT=$(docker exec svveltrobds mysql -uroot -pSlaveDB_V3ltr0_2025! -e "
        SELECT nombre FROM veltro_prod.equipos WHERE nombre='Test_$COUNT';
    " 2>/dev/null | grep "Test_$COUNT")
    
    if [ -n "$RESULT" ]; then
        echo "[$TIMESTAMP] OK - Test $COUNT replicado correctamente"
    else
        echo "[$TIMESTAMP] ERROR - Test $COUNT NO replicado"
    fi
    
    COUNT=$((COUNT + 1))
    sleep 5
done
