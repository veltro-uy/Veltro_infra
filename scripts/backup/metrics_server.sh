#!/bin/bash
METRICS_FILE="/backup/metrics.prom"
PORT=9103

while true; do
    {
        echo -e "HTTP/1.1 200 OK"
        echo -e "Content-Type: text/plain"
        echo -e "Connection: close"
        echo -e ""
        cat $METRICS_FILE 2>/dev/null || echo "# No metrics available"
    } | nc -l -p $PORT -q 1
done
