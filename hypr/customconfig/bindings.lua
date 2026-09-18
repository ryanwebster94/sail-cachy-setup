local mainMod = "SUPER"
local launchPrefix = "uwsm app -- "
local noctCall = "noctalia msg "
local pickerBin = os.getenv("HOME") .. "/.config/quickshell/picker/bin"

hl.unbind(mainMod .. " + W")
hl.unbind(mainMod .. " + T")
hl.unbind(mainMod .. " + Q")

hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(launchPrefix .. "flatpak run app.zen_browser.zen"))
hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.exec_cmd(pickerBin .. "/qs-wallpaper-pick"))
hl.bind(mainMod .. " + SHIFT + CTRL + SPACE", hl.dsp.exec_cmd(pickerBin .. "/qs-folder-pick"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(noctCall .. "panel-toggle session"))
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("steam"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/webapps/bin/qs-webapp-focus apple https://music.apple.com/"))
