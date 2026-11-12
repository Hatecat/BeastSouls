# Servidor de retransmisión (VPS)

Para jugar online sin que nadie abra puertos en su router. Los dos jugadores se conectan al servidor, escriben
la misma **sala** y el servidor los empareja y reenvía sus mensajes. No simula el combate ni decide nada: el
modelo de red es el mismo que en la conexión directa (cada uno simula su Beast; la víctima decide los golpes).
El primero que entra en la sala hace de anfitrión (lleva las rondas y el marcador).

- Puerto: **24700 UDP** (ENet). No usa TCP.
- La compilación del servidor no incluye modelos, texturas ni audio.
- Consumo medido en reposo: ~4 % de un núcleo y ~95 MB de RAM. Admite 64 jugadores a la vez (32 partidas);
  se cambia en `Net.SERVER_MAX_CLIENTS`.
- Cliente y servidor deben tener el mismo `Net.PROTOCOL_VERSION`: al cambiarlo hay que volver a compilar y
  subir el servidor.

## 1. Compilar

```bash
G=~/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path . --export-release "Servidor" builds/server/BeastSoulsServer.x86_64
$G --headless --path . --export-release "Linux"    builds/linux/BeastSouls.x86_64
$G --headless --path . --export-release "Windows"  builds/windows/BeastSouls.exe
```

Los ajustes están en `export_presets.cfg` (fuera de git). El del servidor es un Linux x86_64 con
`dedicated_server=true`, que arranca en `net/relay_server.tscn` (`run/main_scene.dedicated_server` en
project.godot). `builds/` necesita un `.gdignore` dentro: sin él, Godot se cuelga al importar los ejecutables.

## 2. Desplegar (Debian/Ubuntu, como root)

Desde tu PC:

```bash
scp builds/server/BeastSoulsServer.x86_64 deploy/beastsouls-server.service root@TU_VPS:/tmp/
```

En la VPS:

```bash
useradd --system --home /opt/beastsouls --shell /usr/sbin/nologin beastsouls
mkdir -p /opt/beastsouls
mv /tmp/BeastSoulsServer.x86_64 /opt/beastsouls/
chmod +x /opt/beastsouls/BeastSoulsServer.x86_64
chown -R beastsouls:beastsouls /opt/beastsouls
mv /tmp/beastsouls-server.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now beastsouls-server

ufw allow 24700/udp        # si usas ufw; abre también el puerto UDP en el cortafuegos del proveedor
```

Comprobar:

```bash
systemctl status beastsouls-server
journalctl -u beastsouls-server -f      # «servidor de retransmisión · puerto UDP 24700…» y cada sala que se forma
ss -lun | grep 24700
```

Si al arrancar falta alguna biblioteca (VPS mínima): `apt install libfontconfig1`.

Actualizar: subir el ejecutable nuevo a `/opt/beastsouls/` y `systemctl restart beastsouls-server` (corta las
partidas en curso).

## 3. Jugar

Menú → **Jugar online** → en «IP o servidor» la IP o el dominio de la VPS → en «Sala» el mismo código los dos
(sin distinguir mayúsculas; vacío = sala pública, te empareja con el primero que llegue) → **Jugar por
servidor**. La dirección, el nombre y la sala se recuerdan.

Por línea de comandos: `BeastSouls.x86_64 -- --relay=IP --room=CODIGO --nick=NOMBRE`.

## Probar en local

```bash
$G --headless --path . -- --server &
$G --path . -- --relay=127.0.0.1 --room=x --nick=A &
$G --path . -- --relay=127.0.0.1 --room=x --nick=B
```

## Límites actuales

- Sin cifrado ni cuentas: cualquiera que conozca la dirección puede usar el servidor, y quien sepa el código
  de una sala puede entrar en ella antes que tu rival.
- El servidor reenvía sin validar: no evita trampas (igual que en la conexión directa).
- El ping que muestra el panel de depuración es solo tu tramo hasta el servidor; el retardo real con el rival
  es la suma de los dos tramos.
