#!/usr/bin/env bash
# Prueba de replicación sin modificar tablas de la aplicación.

set -Eeuo pipefail

TABLE="replication_check_$$"
MASTER=(docker exec -e MYSQL_PWD=MasterDB_V3ltr0_2025! svveltrobdm mysql -uroot)
SLAVE=(docker exec -e MYSQL_PWD=SlaveDB_V3ltr0_2025! svveltrobds mysql -uroot)

cleanup() {
    "${MASTER[@]}" -e "DROP TABLE IF EXISTS veltro_local.${TABLE};" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${MASTER[@]}" -e "CREATE TABLE veltro_local.${TABLE} (id INT PRIMARY KEY); INSERT INTO veltro_local.${TABLE} VALUES (1);"

for _ in $(seq 1 20); do
    if [ "$("${SLAVE[@]}" -Nse "SELECT COUNT(*) FROM veltro_local.${TABLE};" 2>/dev/null || true)" = "1" ]; then
        echo "OK: escritura de veltro_local replicada correctamente"
        exit 0
    fi
    sleep 1
done

echo "ERROR: la escritura no llegó al Slave en 20 segundos" >&2
exit 1
