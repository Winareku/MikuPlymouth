# Fork notes — Seguridad y robustez

Este repositorio es una bifurcación (fork) orientada a mejorar la seguridad, robustez y las buenas prácticas operativas para desplegar el tema `MikuPlymouth` en sistemas basados en Arch (ej. CachyOS). Se preserva la obra original y el crédito artístico; los cambios se centran en el instalador y el servicio para evitar operaciones peligrosas y trabajos innecesarios en background.

## Audiencia objetivo
- Usuarios de CachyOS / Arch Linux con `systemd-boot` y `mkinitcpio`/UKIs
- Sistemas con X11 (i3wm) donde la pantalla la maneja la GPU integrada (i915) y la GPU dedicada (NVIDIA MX250) se usa bajo demanda
- Entornos donde se desea rotación automática de clips vía `systemd` timer, pero sin reconstruir el initramfs en cada ejecución

## Cambios principales en este fork
- `install.sh`:
  - Activado modo estricto (`set -euo pipefail`) y `trap` para errores.
  - Reemplazo de `ls | ...` y parsing con uso de globs y arrays (`nullglob`) para detectar clips y contar fotogramas dinámicamente.
  - Copiado y borrado de ficheros realizados de forma segura (`cp --`, `rm -f --`) y con comprobaciones de ruta.
  - Añadido flag `--no-initramfs` para evitar reconstrucciones automáticas en ejecuciones por timer.
  - Al final del proceso fija permisos conservadores y propietario (`root:root`), directorios `0755`, ficheros `0644`.
- `miku-rotate.service`:
  - La unidad del servicio ahora llama a `install.sh --no-initramfs` cuando la activa el temporizador.
  - Se añadieron directivas de sandboxing: `ProtectSystem=full`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`.
  - `ReadWritePaths` limitado a `/usr/share/plymouth/themes/MikuPlymouth` y `/opt/MikuPlymouth`.
- `README.md`: añadido aviso de fork y enlace a este fichero con el changelog.

## Recomendaciones de despliegue (seguro)
1. Mover el repositorio a una ubicación permanente y fijar propietarios/permiso antes de habilitar el timer:

```bash
sudo cp -r /ruta/actual/MikuPlymouth /opt/
sudo chown -R root:root /opt/MikuPlymouth
sudo find /opt/MikuPlymouth -type d -exec chmod 0755 {} \;
sudo find /opt/MikuPlymouth -type f -exec chmod 0644 {} \;
sudo chmod 0755 /opt/MikuPlymouth/install.sh
```

2. Instalar la unidad y el temporizador systemd y recargar systemd:

```bash
sudo cp /opt/MikuPlymouth/miku-rotate.service /etc/systemd/system/
sudo cp /opt/MikuPlymouth/miku-rotate.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now miku-rotate.timer
sudo journalctl -u miku-rotate.service -f
```

3. Para la instalación inicial (si quieres incluir los assets en initramfs), ejecuta manualmente sin `--no-initramfs`:

```bash
sudo /opt/MikuPlymouth/install.sh
```

4. Para rotaciones diarias (timer) el servicio ya ejecuta `--no-initramfs` para evitar carga CPU/IO innecesaria.

## Notas legales y de atribución
- Este fork **no** modifica ni reclama la autoría de las animaciones. Mantén el crédito al artista original: [@x_cast_x](https://twitter.com/x_cast_x).
- Asegúrate de respetar cualquier licencia o restricción de uso de los assets antes de redistribuir.

## Cómo contribuir o sincronizar con el upstream
- Añade el remoto upstream y crea PRs contra `Thang1191/MikuPlymouth` si propones cambios que puedan interesar al proyecto original:

```bash
git remote add upstream https://github.com/Thang1191/MikuPlymouth.git
git fetch upstream
git checkout -b my-fixes
# hacer cambios
git commit -am "Security hardening"
git push origin my-fixes
# luego abre PR hacia upstream
```
