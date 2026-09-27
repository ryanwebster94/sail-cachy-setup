local mainMod = "SUPER"
local launchPrefix = "uwsm app -- "
local noctCall = "noctalia msg "
local configHome = os.getenv("XDG_CONFIG_HOME")
if not configHome or configHome == "" then configHome = os.getenv("HOME") .. "/.config" end
local pickerBin = configHome .. "/quickshell/picker/bin"
local function shellQuote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

hl.unbind(mainMod .. " + W")
hl.unbind(mainMod .. " + T")
hl.unbind(mainMod .. " + Q")

hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(launchPrefix .. "flatpak run app.zen_browser.zen"))
hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.exec_cmd(shellQuote(pickerBin .. "/qs-wallpaper-pick")))
hl.bind(mainMod .. " + SHIFT + CTRL + SPACE", hl.dsp.exec_cmd(shellQuote(pickerBin .. "/qs-folder-pick")))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(noctCall .. "panel-toggle session"))
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("steam"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(shellQuote(configHome .. "/webapps/bin/qs-webapp-focus") .. " apple https://music.apple.com/"))
