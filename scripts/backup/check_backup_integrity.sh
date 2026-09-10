#!/bin/bash
################################################################################
# VELTRO - VERIFICACIÓN DE INTEGRIDAD DE BACKUPS
################################################################################

BACKUP_BASE="/backup"

echo "=== VERIFICACIÓN DE INTEGRIDAD ==="
echo "Inicio: $(date)"

TOTAL=0
VALID=0
INVALID=0

echo ""
echo "1. Verificando backups de MySQL..."
for file in $(find $BACKUP_BASE/database -name "*.sql.gz" 2>/dev/null); do
    TOTAL=$((TOTAL + 1))
    if [ -f "${file}.md5" ]; then
        if md5sum -c "${file}.md5" >/dev/null 2>&1; then
            echo "  ✓ $(basename $file)"
            VALID=$((VALID + 1))
        else
            echo "  ✗ $(basename $file) - CHECKSUM FALLIDO"
            INVALID=$((INVALID + 1))
        fi
    else
        echo "  ⚠ $(basename $file) - Sin checksum"
    fi
done

echo ""
echo "2. Verificando backups de Fileserver..."
for file in $(find $BACKUP_BASE/fileserver -name "*.tar.gz" 2>/dev/null); do
    TOTAL=$((TOTAL + 1))
    if [ -f "${file}.md5" ]; then
        if md5sum -c "${file}.md5" >/dev/null 2>&1; then
            echo "  ✓ $(basename $file)"
            VALID=$((VALID + 1))
        else
            echo "  ✗ $(basename $file) - CHECKSUM FALLIDO"
            INVALID=$((INVALID + 1))
        fi
    else
        echo "  ⚠ $(basename $file) - Sin checksum"
    fi
done

echo ""
echo "=== RESUMEN ==="
echo "Total verificados: $TOTAL"
echo "Válidos: $VALID"
echo "Inválidos: $INVALID"

if [ $INVALID -eq 0 ]; then
    echo "✅ Todos los backups están íntegros"
else
    echo "❌ Hay backups corruptos!"
fi

echo "Verificación completada: $(date)"