# OPT1 Operativa Auxiliar y Logística de Oficina

Curso autoguiado de la Unidad 1 **Gestión de suministros y logística interna**, preparado para:

- ejecución directa mediante GitHub Pages;
- identificación individual del alumnado;
- guardado del progreso en un servidor Ubuntu con SQLite;
- reanudación desde otro ordenador o dispositivo;
- seguimiento docente y exportación CSV;
- importación como SCORM 1.2 en Moodle u otro LMS.

## Acceso público

Una vez activado GitHub Pages, el curso se publica en:

`https://atreyu1968.github.io/opt1/`

El panel docente se encuentra en:

`https://atreyu1968.github.io/opt1/admin.html`

El primer acceso debe indicar la dirección pública de la API. Puede enviarse ya configurada en el enlace:

`https://atreyu1968.github.io/opt1/?api=https://DOMINIO-DE-LA-API`

La dirección queda guardada en el navegador y desaparece de la barra de direcciones.

## Instalación desde un servidor Ubuntu completamente vacío

Estas instrucciones sirven para Ubuntu Server 22.04 o 24.04 recién instalado, aunque no tenga `git`, `curl`, Node.js ni ninguna dependencia.

### 1 Actualizar el sistema e instalar las herramientas básicas

Acceda por SSH y ejecute:

```bash
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
sudo apt install -y git curl ca-certificates gnupg unzip
```

Compruebe que Git y Curl funcionan:

```bash
git --version
curl --version
```

### 2 Descargar OPT1

```bash
git clone https://github.com/atreyu1968/opt1.git
cd opt1
```

Si la carpeta `opt1` ya existe porque está actualizando una instalación anterior:

```bash
cd opt1
git pull --ff-only
```

### 3 Ejecutar el instalador automático

```bash
sudo bash install.sh
```

El instalador solicitará el dominio HTTPS de la API, por ejemplo `https://opt1.iesmmg.org`. Después:

- instala Node.js 22 cuando resulte necesario;
- crea el usuario de sistema `opt1`;
- instala la aplicación en `/opt/opt1`;
- crea la base de datos en `/var/lib/opt1/opt1.sqlite`;
- registra y activa el servicio `opt1.service`;
- inicia la aplicación en el puerto 8080.

No es necesario ejecutar `npm install`: el servidor utiliza las funciones integradas de Node.js 22 y no depende de paquetes externos.

### 4 Comprobar el servicio

```bash
sudo systemctl status opt1 --no-pager
curl http://127.0.0.1:8080/api/health
```

La segunda orden debe devolver un objeto con `"ok":true`.

Para consultar los últimos mensajes del servicio:

```bash
sudo journalctl -u opt1 -n 100 --no-pager
```

### 5 Cortafuegos

Si utiliza UFW y va a acceder directamente al puerto 8080 desde la red local:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw status
```

Si usa Cloudflare Tunnel en el mismo servidor, no necesita abrir públicamente el puerto 8080. Manténgalo accesible solo desde `localhost` a través del túnel.

## Configuración

Edite:

```bash
sudo nano /opt/opt1/server/.env
```

Ejemplo:

```ini
PORT=8080
HOST=0.0.0.0
DATA_DIR=/var/lib/opt1
PUBLIC_ORIGINS=https://atreyu1968.github.io,https://opt1.iesmmg.org
SESSION_HOURS=168
TRUST_PROXY=1
```

Después de modificarlo:

```bash
sudo systemctl restart opt1
sudo systemctl status opt1 --no-pager
```

## Primera puesta en marcha

1. Abra `https://DOMINIO-DE-LA-API/admin.html` o el panel de GitHub Pages.
2. Indique la dirección pública de la API.
3. El sistema detectará que no existe administración y solicitará un usuario y una contraseña de al menos diez caracteres.
4. Entre en el panel docente.
5. Entregue al alumnado el enlace del curso con el parámetro `?api=`.

## Funcionamiento del alumnado

En el primer acceso, el alumno registra nombre, apellidos, grupo y un PIN de 4 a 8 cifras. El sistema genera un código del tipo `OPT-A1B2C3`. El alumno debe conservar ese código para volver a entrar.

El servidor guarda:

- misión actual;
- actividades superadas;
- borradores del dossier;
- intento y calificación de la evaluación;
- fecha de actualización y última conexión.

## Panel docente

El panel permite:

- consultar alumnos por nombre, código y grupo;
- filtrar por estado;
- ver puntuación y última conexión;
- restablecer el PIN a `1234`;
- exportar el seguimiento en CSV.

## Publicación con Cloudflare Tunnel

El servicio escucha en `http://localhost:8080`. En Cloudflare Tunnel, cree un hostname público, por ejemplo `opt1.iesmmg.org`, dirigido a:

`http://localhost:8080`

Use siempre HTTPS en la dirección pública. GitHub Pages no permitirá conectarse a una API HTTP insegura.

Si `cloudflared` todavía no está instalado, utilice el comando de instalación que proporciona Cloudflare al crear el túnel desde **Zero Trust > Networks > Tunnels**. Después, añada un hostname público con estos datos:

- Subdominio: el elegido, por ejemplo `opt1`.
- Dominio: su dominio educativo.
- Tipo de servicio: `HTTP`.
- URL de destino: `localhost:8080`.

Compruebe desde otro equipo:

```bash
curl https://DOMINIO-DE-LA-API/api/health
```

No continúe con el alumnado hasta que esta dirección devuelva `"ok":true`.

## Actualización

```bash
cd opt1
git pull --ff-only
sudo bash install.sh
```

La base de datos permanece en `/var/lib/opt1` y no se elimina durante la actualización.

## Desinstalación conservando una copia

Antes de retirar la aplicación, guarde la base de datos. Después:

```bash
sudo systemctl disable --now opt1
sudo cp /var/lib/opt1/opt1.sqlite /ruta/segura/opt1-ultima-copia.sqlite
sudo rm /etc/systemd/system/opt1.service
sudo systemctl daemon-reload
```

Los directorios `/opt/opt1` y `/var/lib/opt1` pueden conservarse hasta confirmar que ya no necesita recuperar información.

## Solución de problemas

### El servicio no arranca

```bash
node --version
sudo journalctl -u opt1 -n 100 --no-pager
```

OPT1 necesita Node.js 22 o posterior. Puede volver a ejecutar `sudo bash install.sh`; el instalador es idempotente y no borra la base de datos.

### GitHub Pages abre el curso, pero no guarda el progreso

Compruebe:

1. Que el enlace contiene `?api=https://DOMINIO-DE-LA-API`.
2. Que la API responde en `/api/health`.
3. Que `PUBLIC_ORIGINS` contiene `https://atreyu1968.github.io`.
4. Que tanto GitHub Pages como la API utilizan HTTPS.

### Error de origen o CORS

Edite `/opt/opt1/server/.env` y deje los orígenes separados por comas, sin rutas:

```ini
PUBLIC_ORIGINS=https://atreyu1968.github.io,https://opt1.iesmmg.org
```

Reinicie:

```bash
sudo systemctl restart opt1
```

## Copia de seguridad

```bash
sudo systemctl stop opt1
sudo cp /var/lib/opt1/opt1.sqlite /ruta/segura/opt1-$(date +%F).sqlite
sudo systemctl start opt1
```

## SCORM 1.2

Para crear el paquete SCORM, comprima el contenido de la carpeta `web` asegurándose de que `imsmanifest.xml` quede en la raíz del ZIP. Cuando el curso se ejecuta desde un LMS con API SCORM, utiliza la identidad, el progreso y la calificación suministrados por el propio LMS y no muestra el registro externo.

## Privacidad

La aplicación recoge únicamente los datos necesarios para identificar al alumno y guardar su progreso. El centro debe informar sobre el tratamiento, establecer un periodo de conservación y limitar el acceso al panel docente. No se incluyen servicios publicitarios ni herramientas de seguimiento externas.

## Licencia y autoría

Material educativo elaborado por Francisco Javier González Rolo para el IES Manuel Martín González. Curso académico 2026–2027.
