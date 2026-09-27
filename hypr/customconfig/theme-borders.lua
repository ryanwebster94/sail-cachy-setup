-- theme-borders.lua — window/group borders follow the Noctalia wallpaper theme.
-- Overrides the hardcoded Cachy palette in ~/.config/hypr/config/decorations.lua
-- (which stays Noctalia-managed and is intentionally left untouched) by
-- re-applying Noctalia's generated palette (~/.config/hypr/noctalia.lua,
-- produced by the builtin `hyprland` theme template on every wallpaper switch).
-- Loaded last via customconfig/bindings.lua so it wins over config/*. Safe
-- no-op when noctalia.lua is absent (fresh machine before first Noctalia run).
pcall(function()
  local ok, noct = pcall(require, "noctalia")
  if ok and noct and noct.apply_theme then
    noct.apply_theme()
  end
end)
