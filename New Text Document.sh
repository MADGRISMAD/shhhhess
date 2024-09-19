#!/bin/bash

# Definir las rutas y variables
LOCAL_REPO="/mnt/c/Users/ManuelSabinoAndrés/Desktop/AS3-Portal-Frontend"
DIST_DIR="$LOCAL_REPO/dist"
ZIP_FILE="$LOCAL_REPO/dist.zip"
REMOTE_USER="ec2-user"
REMOTE_HOST="as3international.com"
PEM_FILE="~/aws_keys/AWS-KeyPair-Manuel.pem"
REMOTE_PATH="/home/ec2-user/"
LOG_FILE="deploy_log.txt"

# Token de acceso personal de GitHub (obtenido de la variable de entorno)
GITHUB_USERNAME="ManuelSabino"
GITHUB_TOKEN=$GITHUB_TOKEN

# Redirigir toda la salida a un archivo de log
exec > >(tee -a $LOG_FILE) 2>&1

echo "Iniciando el script de despliegue..."

# Función para pausar en caso de error
pause_on_fail() {
    echo "Fallo en la ejecución. Pulsa cualquier tecla para continuar y revisar..."
    read -n 1 -s
}

# Navegar al directorio del repositorio
cd $LOCAL_REPO || { echo "Error: No se puede acceder al repositorio"; pause_on_fail; }

# Agregar credenciales para GitHub temporalmente
git config credential.helper store
echo "https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com" > ~/.git-credentials

# Hacer fetch para traer información de la rama remota
echo "Haciendo git fetch para actualizar las referencias remotas..."
git fetch origin || { echo "Error: No se pudo hacer fetch desde 'origin'"; pause_on_fail; }

# Hacer checkout forzado a la rama production
echo "Haciendo checkout forzado a la rama 'production'..."
git checkout -f production || { echo "Error: No se pudo hacer checkout forzado a 'production'"; pause_on_fail; }

# Hacer git pull para traer los cambios más recientes de la rama production
echo "Haciendo git pull desde 'origin production'..."
git pull origin production || { echo "Error: No se pudo hacer pull desde 'origin production'"; pause_on_fail; }

# Eliminar la carpeta dist y el archivo dist.zip si existen
echo "Eliminando cualquier rastro de la carpeta dist y dist.zip anteriores..."
rm -rf $LOCAL_REPO/dist
rm -f $ZIP_FILE

# Ejecutar el build de Angular (sin --prod)
echo "Ejecutando 'ng build'..."
ng build || { echo "Error: Falló el ng build"; pause_on_fail; }

# Comprimir la carpeta dist
echo "Comprimiendo la carpeta dist en $ZIP_FILE..."
cd $LOCAL_REPO && zip -r $ZIP_FILE dist || { echo "Error: No se pudo comprimir la carpeta dist"; pause_on_fail; }

# Verificar que el archivo dist.zip existe
if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: El archivo dist.zip no se creó correctamente."
    pause_on_fail
fi

# Transferir el archivo dist.zip a la instancia EC2
echo "Transfiriendo $ZIP_FILE a $REMOTE_HOST:$REMOTE_PATH ..."
scp -i $PEM_FILE $ZIP_FILE $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH || { echo "Error: Falló la transferencia del archivo"; pause_on_fail; }

# Conectar a la instancia EC2 y ejecutar los scripts
echo "Conectando a la instancia EC2 y ejecutando los scripts..."
ssh -i $PEM_FILE $REMOTE_USER@$REMOTE_HOST << 'EOF'
  # Eliminar la carpeta dist si existe en la instancia
  if [ -d "/home/ec2-user/dist" ]; then
    echo "Carpeta dist encontrada, eliminando..."
    rm -rf /home/ec2-user/dist
  fi
  
  # Ejecutar el script de actualización (que descomprime, mueve archivos y reinicia nginx)
  echo "Ejecutando actualizar_as3_portal.sh ..."
  bash actualizar_as3_portal.sh
  
  # Ejecutar el script de limpieza
  echo "Ejecutando eliminar_dist.sh ..."
  bash eliminar_dist.sh
EOF

echo "Despliegue completado. Logs guardados en $LOG_FILE."
