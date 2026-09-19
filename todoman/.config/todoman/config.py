# Configuración de todoman para icloud-glass.
#
# Igual que con khal: `icloud-glass-sync` genera su propia configuración de
# todoman en un directorio temporal en cada ejecución (para respetar
# ICLOUD_GLASS_VDIR/--vdir en los tests), y solo la usa como comprobación de
# salud de la herramienta, no como fuente de datos (ver el comentario en
# icloud-glass-sync sobre por qué: --porcelain no expone 'uid' ni 'created').
# Este archivo es para el uso interactivo de `todo` desde la terminal.
#
# todoman respeta $XDG_DATA_HOME/$XDG_CONFIG_HOME de forma nativa; no hace
# falta configurarlo aparte.

path = "~/.local/share/icloud-glass/vdir/reminders/*"

date_format = "%d/%m/%Y"
time_format = "%H:%M"

# Ninguna lista por defecto: con varias listas de iCloud Reminders
# descubiertas, no hay una "correcta" a priori. El panel decide
# (shell.json -> defaultList) y pasa la lista explícitamente.
default_list = None
