#!/bin/bash
################################################################################
# VELTRO - VERIFICACIÓN DE INTEGRIDAD DE BACKUPS
################################################################################

set -e

BACKUP_BASE="/backup"
LOG_FILE="/var/log/backup/check_$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

exec > >(tee -a $LOG_FILE) 2>&1

echo "=== VERIFICACIÓN DE INTEGRIDAD - $(date) ==="
echo ""

# Variables
TOTAL=0
VALID=0
INVALID=0

# Verificar backups de MySQL
echo "1. Verificando backups de MySQL..."
for file in $(find $BACKUP_BASE/database -name "*.sql.gz" 2>/dev/null); do
    TOTAL=$((TOTAL + 1))
    if [ -f "${file}.md5" ]; then
        if md5sum -c "${file}.md5" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $(basename $file)"
            VALID=$((VALID + 1))
        else
            echo -e "  ${RED}✗${NC} $(basename $file) - CHECKSUM FALLIDO"
            INVALID=$((INVALID + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} $(basename $file) - Sin checksum"
        # Generar checksum faltante
        md5sum "$file" > "${file}.md5"
        echo "    Checksum generado"
    fi
done

# Verificar backups de Fileserver
echo ""
echo "2. Verificando backups de Fileserver..."
for file in $(find $BACKUP_BASE/fileserver -name "*.tar.gz" 2>/dev/null); do
    TOTAL=$((TOTAL + 1))
    if [ -f "${file}.md5" ]; then
        if md5sum -c "${file}.md5" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $(basename $file)"
            VALID=$((VALID + 1))
        else
            echo -e "  ${RED}✗${NC} $(basename $file) - CHECKSUM FALLIDO"
            INVALID=$((INVALID + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} $(basename $file) - Sin checksum"
        md5sum "$file" > "${file}.md5"
        echo "    Checksum generado"
    fi
done

# Resumen
echo ""
echo "=== RESUMEN ==="
echo "Total verificados: $TOTAL"
echo -e "${GREEN}Válidos: $VALID${NC}"
echo -e "${RED}Inválidos: $INVALID${NC}"

if [ $INVALID -eq 0 ]; then
    echo -e "${GREEN}✓ Todos los backups están íntegros${NC}"
else
    echo -e "${RED}✗ Hay backups corruptos!${NC}"
fi

echo ""
echo "=== FIN VERIFICACIÓN - $(date) ==="