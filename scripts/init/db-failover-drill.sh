#!/usr/bin/env bash

# Failover manual y recuperación de la topología MySQL de Veltro.
#
# Uso:
#   ./scripts/init/db-failover-drill.sh status
#   ./scripts/init/db-failover-drill.sh failover
#   ./scripts/init/db-failover-drill.sh restore
#
# Agregá --yes únicamente para ejecución no interactiva.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAPROXY_CONFIG="$ROOT_DIR/config/haproxy/haproxy.cfg"
MASTER_DATA="$ROOT_DIR/data/db-master"
MASTER_CONTAINER="svveltrobdm"
SLAVE_CONTAINER="svveltrobds"
MASTER_IP="192.168.20.20"
SLAVE_IP="192.168.20.40"
MASTER_ROOT_PASSWORD="${MASTER_ROOT_PASSWORD:-MasterDB_V3ltr0_2025!}"
SLAVE_ROOT_PASSWORD="${SLAVE_ROOT_PASSWORD:-SlaveDB_V3ltr0_2025!}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-Replicator_V3ltr0_2025!}"
APP_SERVICES=(svveltroweb svveltroqueue svveltroscheduler svveltroreverb)
ASSUME_YES=0

cd "$ROOT_DIR"

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf 'OK: %s\n' "$*"; }
warn() { printf 'ADVERTENCIA: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

master_mysql() {
    docker exec -e MYSQL_PWD="$MASTER_ROOT_PASSWORD" "$MASTER_CONTAINER" mysql -uroot "$@"
}

slave_mysql() {
    docker exec -e MYSQL_PWD="$SLAVE_ROOT_PASSWORD" "$SLAVE_CONTAINER" mysql -uroot "$@"
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" = "true" ]
}

haproxy_write_target() {
    awk '$1 == "server" && $2 == "master" { split($3, address, ":"); print address[1] }' "$HAPROXY_CONFIG"
}

replica_field() {
    local field="$1"
    local output="$2"
    awk -F': ' -v field="$field" '$1 ~ "^[[:space:]]*" field "$" { print $2; exit }' <<<"$output"
}

confirm() {
    local expected="$1"
    local prompt="$2"
    local answer

    [ "$ASSUME_YES" -eq 1 ] && return
    [ -t 0 ] || die "La operación requiere confirmación interactiva o --yes."
    printf '%s\nEscribí %s para continuar: ' "$prompt" "$expected"
    read -r answer
    [ "$answer" = "$expected" ] || die "Operación cancelada."
}

stop_app() {
    docker compose stop "${APP_SERVICES[@]}"
}

start_app() {
    # docker compose start sigue depends_on y puede revivir el master aislado.
    docker start "${APP_SERVICES[@]}"
}

wait_healthy() {
    local container="$1"
    local health_state

    for _ in $(seq 1 60); do
        health_state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
        [ "$health_state" = "healthy" ] && return
        sleep 2
    done

    docker logs --tail 80 "$container" >&2 || true
    die "$container no quedó healthy dentro de 120 segundos."
}

wait_for_gtids() {
    local source_gtids
    local result

    source_gtids="$(slave_mysql -Nse 'SELECT @@GLOBAL.gtid_executed')"
    result="$(master_mysql -Nse "SELECT WAIT_FOR_EXECUTED_GTID_SET('${source_gtids}', 60)")"
    [ "$result" = "0" ] || die "El master reconstruido no alcanzó al primario promovido."
}

wait_original_replica() {
    local replica_status
    local io_running
    local sql_running

    for _ in $(seq 1 30); do
        replica_status="$(slave_mysql -e 'SHOW REPLICA STATUS\G' 2>/dev/null || true)"
        io_running="$(replica_field Replica_IO_Running "$replica_status")"
        sql_running="$(replica_field Replica_SQL_Running "$replica_status")"
        if [ "$io_running" = "Yes" ] && [ "$sql_running" = "Yes" ]; then
            return
        fi
        sleep 2
    done

    printf '%s\n' "$replica_status" >&2
    die "La réplica original no inició correctamente."
}

route_writes_to() {
    local target_ip="$1"
    local current_ip

    current_ip="$(haproxy_write_target)"
    [ "$current_ip" = "$target_ip" ] && return

    if [ "$current_ip" = "$MASTER_IP" ] && [ "$target_ip" = "$SLAVE_IP" ]; then
        sed -i "s/server master ${MASTER_IP}:3306/server master ${SLAVE_IP}:3306/" "$HAPROXY_CONFIG"
    elif [ "$current_ip" = "$SLAVE_IP" ] && [ "$target_ip" = "$MASTER_IP" ]; then
        sed -i "s/server master ${SLAVE_IP}:3306/server master ${MASTER_IP}:3306/" "$HAPROXY_CONFIG"
    else
        die "Destino de HAProxy inesperado: ${current_ip:-desconocido}."
    fi

    docker exec sqlproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
    docker compose restart sqlproxy
}

data_hash() {
    local container="$1"
    local password="$2"

    docker exec -e MYSQL_PWD="$password" "$container" mysqldump -uroot \
        --single-transaction \
        --set-gtid-purged=OFF \
        --skip-comments \
        --compact \
        --order-by-primary \
        --no-create-info \
        --databases veltro_local 2>/dev/null |
        sha256sum | awk '{print $1}'
}

show_status() {
    local target
    local replica_status

    target="$(haproxy_write_target)"
    docker compose ps "$MASTER_CONTAINER" "$SLAVE_CONTAINER" sqlproxy svveltroweb
    printf '\nHAProxy escritura: %s:3306\n' "${target:-desconocido}"

    if container_running "$MASTER_CONTAINER"; then
        master_mysql -Nse "SELECT CONCAT(@@hostname, ': read_only=', @@read_only, ', super_read_only=', @@super_read_only)" || true
    else
        printf '%s: detenido\n' "$MASTER_CONTAINER"
    fi

    if container_running "$SLAVE_CONTAINER"; then
        slave_mysql -Nse "SELECT CONCAT(@@hostname, ': read_only=', @@read_only, ', super_read_only=', @@super_read_only)" || true
        replica_status="$(slave_mysql -e 'SHOW REPLICA STATUS\G' 2>/dev/null || true)"
        if [ -n "$replica_status" ]; then
            printf 'Replica_IO_Running=%s, Replica_SQL_Running=%s, lag=%s\n' \
                "$(replica_field Replica_IO_Running "$replica_status")" \
                "$(replica_field Replica_SQL_Running "$replica_status")" \
                "$(replica_field Seconds_Behind_Source "$replica_status")"
        else
            printf 'Replicación detenida: este nodo está promovido.\n'
        fi
    else
        printf '%s: detenido\n' "$SLAVE_CONTAINER"
    fi
}

failover() {
    local replica_status
    local master_gtids
    local wait_result
    local timestamp
    local drill_dir

    [ "$(haproxy_write_target)" = "$MASTER_IP" ] || die "HAProxy no apunta al master original. Ejecutá status."
    container_running "$MASTER_CONTAINER" || die "$MASTER_CONTAINER no está corriendo."
    container_running "$SLAVE_CONTAINER" || die "$SLAVE_CONTAINER no está corriendo."
    [ "$(master_mysql -Nse 'SELECT @@read_only')" = "0" ] || die "$MASTER_CONTAINER no está habilitado para escrituras."
    [ "$(slave_mysql -Nse 'SELECT @@read_only')" = "1" ] || die "$SLAVE_CONTAINER no está en modo solo lectura."

    replica_status="$(slave_mysql -e 'SHOW REPLICA STATUS\G')"
    [ "$(replica_field Replica_IO_Running "$replica_status")" = "Yes" ] || die "Replica_IO_Running no está en Yes."
    [ "$(replica_field Replica_SQL_Running "$replica_status")" = "Yes" ] || die "Replica_SQL_Running no está en Yes."
    [ "$(replica_field Seconds_Behind_Source "$replica_status")" = "0" ] || die "La réplica tiene retraso."

    confirm FAILOVER "Se detendrá Laravel, se apagará $MASTER_CONTAINER y $SLAVE_CONTAINER quedará como primario."

    timestamp="$(date +%Y%m%d-%H%M%S)"
    drill_dir="$ROOT_DIR/data/failover-drill-$timestamp"
    mkdir -p "$drill_dir"
    cp "$HAPROXY_CONFIG" "$drill_dir/haproxy.cfg.before-failover"

    log "Deteniendo productores de escrituras"
    stop_app

    master_gtids="$(master_mysql -Nse 'SELECT @@GLOBAL.gtid_executed')"
    wait_result="$(slave_mysql -Nse "SELECT WAIT_FOR_EXECUTED_GTID_SET('${master_gtids}', 60)")"
    [ "$wait_result" = "0" ] || die "La réplica no alcanzó al master; Laravel permanece detenido."

    log "Creando respaldo previo"
    docker exec -e MYSQL_PWD="$MASTER_ROOT_PASSWORD" "$MASTER_CONTAINER" mysqldump -uroot \
        --single-transaction \
        --source-data=2 \
        --set-gtid-purged=ON \
        --routines --triggers --events \
        --databases veltro_local 2>"$drill_dir/mysqldump.stderr" |
        gzip >"$drill_dir/pre-failover.sql.gz"
    gzip -t "$drill_dir/pre-failover.sql.gz"

    log "Deteniendo master y promoviendo réplica"
    docker compose stop "$MASTER_CONTAINER"
    slave_mysql -e "STOP REPLICA; RESET REPLICA ALL; SET PERSIST read_only=OFF; SET PERSIST super_read_only=OFF;"
    route_writes_to "$SLAVE_IP"

    log "Reactivando Laravel"
    start_app

    slave_mysql -Nse "SELECT CONCAT(@@hostname, ': read_only=', @@read_only)"
    docker exec svveltroweb php artisan tinker --execute="DB::statement('CREATE TEMPORARY TABLE failover_smoke (id INT)'); DB::table('failover_smoke')->insert(['id' => 1]); dump(DB::selectOne('SELECT @@hostname AS host, @@read_only AS read_only, (SELECT COUNT(*) FROM failover_smoke) AS rows_written'));"

    ok "Failover completado. Respaldo: $drill_dir"
    warn "No ejecutes 'docker compose up -d' ni inicies $MASTER_CONTAINER. Para volver: $0 restore"
}

restore() {
    local timestamp
    local recovery_dir
    local old_master_data
    local source_gtids
    local wait_result
    local source_hash
    local target_hash

    [ "$(haproxy_write_target)" = "$SLAVE_IP" ] || die "HAProxy no apunta al primario promovido. Ejecutá status."
    container_running "$SLAVE_CONTAINER" || die "$SLAVE_CONTAINER no está corriendo."
    [ "$(slave_mysql -Nse 'SELECT @@read_only')" = "0" ] || die "$SLAVE_CONTAINER no está habilitado para escrituras."

    confirm RESTORE "Se reconstruirá por completo data/db-master desde el primario promovido y luego se restaurarán los roles originales."

    timestamp="$(date +%Y%m%d-%H%M%S)"
    recovery_dir="$ROOT_DIR/data/failover-recovery-$timestamp"
    old_master_data="$ROOT_DIR/data/db-master-before-rebuild-$timestamp"
    mkdir -p "$recovery_dir"
    cp "$HAPROXY_CONFIG" "$recovery_dir/haproxy.cfg.before-restore"

    log "Respaldando el primario promovido"
    docker exec -e MYSQL_PWD="$SLAVE_ROOT_PASSWORD" "$SLAVE_CONTAINER" mysqldump -uroot \
        --single-transaction \
        --source-data=2 \
        --set-gtid-purged=ON \
        --routines --triggers --events \
        --databases veltro_local 2>"$recovery_dir/mysqldump.stderr" |
        gzip >"$recovery_dir/promoted-primary.sql.gz"
    gzip -t "$recovery_dir/promoted-primary.sql.gz"

    log "Apartando el volumen viejo y recreando $MASTER_CONTAINER"
    docker compose stop "$MASTER_CONTAINER"
    docker compose rm -f "$MASTER_CONTAINER"
    [ -d "$MASTER_DATA" ] || die "No existe $MASTER_DATA."
    [ ! -e "$old_master_data" ] || die "Ya existe $old_master_data."
    mv "$MASTER_DATA" "$old_master_data"
    mkdir "$MASTER_DATA"
    docker compose up -d "$MASTER_CONTAINER"
    wait_healthy "$MASTER_CONTAINER"

    log "Restaurando datos y GTID"
    master_mysql -e "DROP DATABASE IF EXISTS veltro_local; RESET MASTER;"
    gzip -dc "$recovery_dir/promoted-primary.sql.gz" |
        docker exec -i -e MYSQL_PWD="$MASTER_ROOT_PASSWORD" "$MASTER_CONTAINER" mysql -uroot

    slave_mysql -e "CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY '${REPLICATION_PASSWORD}'; ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY '${REPLICATION_PASSWORD}'; GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%'; FLUSH PRIVILEGES;"
    master_mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${SLAVE_CONTAINER}', SOURCE_PORT=3306, SOURCE_USER='replicator', SOURCE_PASSWORD='${REPLICATION_PASSWORD}', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1; START REPLICA; SET GLOBAL read_only=ON; SET GLOBAL super_read_only=ON;"
    wait_for_gtids

    log "Pausando escrituras para el cambio de regreso"
    stop_app
    wait_for_gtids

    source_hash="$(data_hash "$SLAVE_CONTAINER" "$SLAVE_ROOT_PASSWORD")"
    target_hash="$(data_hash "$MASTER_CONTAINER" "$MASTER_ROOT_PASSWORD")"
    [ "$source_hash" = "$target_hash" ] || die "Los datos no coinciden; Laravel permanece detenido y no se cambió el primario."

    log "Restaurando roles originales"
    slave_mysql -e "SET PERSIST read_only=ON; SET PERSIST super_read_only=ON;"
    master_mysql -e "STOP REPLICA; RESET REPLICA ALL; SET PERSIST read_only=OFF; SET PERSIST super_read_only=OFF;"
    slave_mysql -e "RESET REPLICA ALL; CHANGE REPLICATION SOURCE TO SOURCE_HOST='${MASTER_CONTAINER}', SOURCE_PORT=3306, SOURCE_USER='replicator', SOURCE_PASSWORD='${REPLICATION_PASSWORD}', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1; START REPLICA;"
    route_writes_to "$MASTER_IP"
    wait_original_replica

    log "Reactivando Laravel"
    start_app
    docker exec svveltroweb php artisan tinker --execute="dump(DB::selectOne('SELECT @@hostname AS host, @@read_only AS read_only'));"

    ok "Topología original restaurada. Volumen anterior conservado en: $old_master_data"
    ok "Respaldo SQL conservado en: $recovery_dir"
}

usage() {
    cat <<'EOF'
Uso: db-failover-drill.sh <status|failover|restore> [--yes]

  status    Muestra el destino de HAProxy y el estado de ambos MySQL.
  failover  Promueve svveltrobds de forma controlada.
  restore   Reconstruye svveltrobdm y recupera los roles originales.
  --yes     Omite la confirmación interactiva.
EOF
}

main() {
    local action="${1:-status}"

    [ "${2:-}" != "--yes" ] || ASSUME_YES=1
    mkdir -p "$ROOT_DIR/data"
    exec 9>"$ROOT_DIR/data/.db-failover.lock"
    flock -n 9 || die "Ya hay otra operación de failover ejecutándose."

    case "$action" in
        status)   show_status ;;
        failover) failover ;;
        restore)  restore ;;
        -h|--help|help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
