#!/bin/bash
################################################################################
# VELTRO - Configuración SSH en la máquina anfitriona
# Ejecutar DESPUÉS de que los contenedores estén corriendo
################################################################################

echo "=== VELTRO - Configurando SSH ==="

# 1. Crear directorio .ssh si no existe
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 2. Copiar la clave del Backup Server
echo "Copiando clave SSH del Backup Server..."
docker cp svveltrobackup:/home/backup/.ssh/id_rsa ~/.ssh/id_rsa_backup
docker cp svveltrobackup:/home/backup/.ssh/id_rsa.pub ~/.ssh/id_rsa_backup.pub
chmod 600 ~/.ssh/id_rsa_backup
chmod 644 ~/.ssh/id_rsa_backup.pub
echo "✓ Clave copiada"

# 3. Agregar la clave pública al File Server
echo "Agregando clave al File Server..."
PUB_KEY=$(cat ~/.ssh/id_rsa_backup.pub)
docker exec fileserver bash -c "mkdir -p /home/mlopez/.ssh && echo '$PUB_KEY' >> /home/mlopez/.ssh/authorized_keys && chmod 600 /home/mlopez/.ssh/authorized_keys && chmod 700 /home/mlopez/.ssh && chown -R mlopez:mlopez /home/mlopez/.ssh"
echo "✓ Clave agregada al File Server"

# 4. Configurar acceso SSH
echo "Configurando ~/.ssh/config..."
cat > ~/.ssh/config << 'EOF'
Host backup
    HostName localhost
    Port 2022
    User backup
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host fileserver
    HostName localhost
    Port 2322
    User mlopez
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 ~/.ssh/config
echo "✓ Configuración SSH actualizada"

# 5. Probar conexiones
echo ""
echo "=== Probando conexiones ==="

echo -n "Backup Server: "
if ssh -o ConnectTimeout=5 backup "echo OK" 2>/dev/null; then
    echo "✅ OK"
else
    echo "❌ ERROR"
fi

echo -n "File Server: "
if ssh -o ConnectTimeout=5 fileserver "echo OK" 2>/dev/null; then
    echo "✅ OK"
else
    echo "❌ ERROR"
fi

echo ""
echo "=== CONFIGURACIÓN SSH COMPLETADA ==="
echo "Ahora puedes conectarte con:"
echo "  ssh backup"
echo "  ssh fileserver"