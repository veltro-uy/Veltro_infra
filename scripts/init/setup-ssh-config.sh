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

docker exec fileserver bash -c '
for u in mlopez fmartinez ngalego mlandaco pfumero
do
    mkdir -p /home/$u/.ssh
    echo "'"$PUB_KEY"'" > /home/$u/.ssh/authorized_keys
    chmod 700 /home/$u/.ssh
    chmod 600 /home/$u/.ssh/authorized_keys
    chown -R $u:$u /home/$u/.ssh
done
'

echo "✓ Clave agregada a todos los usuarios del File Server"

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

Host mlopez
    HostName localhost
    Port 2322
    User mlopez
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host fmartinez 
    HostName localhost
    Port 2322
    User fmartinez
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host ngalego
    HostName localhost
    Port 2322
    User ngalego
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host mlandaco
    HostName localhost
    Port 2322
    User mlandaco
    IdentityFile ~/.ssh/id_rsa_backup
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host pfumero
    HostName localhost
    Port 2322
    User pfumero
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

echo -n "File Server (mlopez): "
if ssh -o ConnectTimeout=5 mlopez "echo OK" 2>/dev/null; then
    echo "✅ OK"
else
    echo "❌ ERROR"
fi

echo ""
echo "=== CONFIGURACIÓN SSH COMPLETADA ==="
echo "Ahora puedes acceder por SSH a los servidores con los siguientes alias:"
echo ""
echo "  Backup Server:"
echo "    ssh backup"
echo ""
echo "  File Server:"
echo "    ssh mlopez"
echo "    ssh fmartinez"
echo "    ssh ngalego"
echo "    ssh mlandaco"
echo "    ssh pfumero"