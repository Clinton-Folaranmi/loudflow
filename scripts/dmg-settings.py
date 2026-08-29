# dmgbuild settings for the LoudFlow installer DMG.
# Invoked by scripts/make-dmg.sh:  dmgbuild -s scripts/dmg-settings.py -D app=... -D bg=... "LoudFlow X" out.dmg
import os.path

app = defines.get("app", "/Applications/LoudFlow.app")
bg = defines.get("bg")
appname = os.path.basename(app)

# Disk image
format = "UDZO"                       # compressed, read-only
files = [app]
symlinks = {"Applications": "/Applications"}

# Window + layout (matches the arrow positions in dmg-bg.png)
background = bg
window_rect = ((200, 120), (600, 400))
default_view = "icon-view"
icon_size = 120
text_size = 13
icon_locations = {
    appname: (150, 200),
    "Applications": (450, 200),
}
