-- Toolbox_ui.lua — fenêtres nettes sur les écrans haute densité (Mac Retina, Windows à 150 %…).
-- Les scripts dessinent en « points » (coordonnées logiques) ; ici on demande à REAPER une fenêtre à pleine
-- résolution et on convertit dessins, polices et souris. Sans écran haute densité, rien ne change.
-- Utilisation : U.init(titre, l, h, ancrage) à la place de gfx.init, puis U.frame() juste après gfx.getchar().
local U = { R = 1 }
local raw = {}

local function wrap()
  local R = gfx.ext_retina or 1
  if R < 1.05 then
    U.R = 1
    for k, f in pairs(raw) do gfx[k] = f end              -- retour sur un écran normal : fonctions d'origine
    return
  end
  U.R = R
  if not raw.rect then
    for _, k in ipairs({ "rect", "line", "circle", "setfont", "measurestr", "drawstr" }) do raw[k] = gfx[k] end
  end
  gfx.rect = function(x, y, w, h, f) return raw.rect(x * R, y * R, w * R, h * R, f) end
  gfx.line = function(x1, y1, x2, y2, aa) return raw.line(x1 * R, y1 * R, x2 * R, y2 * R, aa) end
  gfx.circle = function(x, y, r, f, aa) return raw.circle(x * R, y * R, r * R, f, aa) end
  gfx.setfont = function(i, face, sz, flags)
    local r
    if face then r = raw.setfont(i, face, (sz or 12) * R, flags) else r = raw.setfont(i) end
    gfx.texth = (gfx.texth or 12) / R
    return r
  end
  gfx.measurestr = function(s) local w, h = raw.measurestr(s); return (w or 0) / R, (h or gfx.texth * R) / R end
  gfx.drawstr = function(s, ...)
    local x, y = gfx.x, gfx.y
    gfx.x, gfx.y = x * R, y * R
    local r = raw.drawstr(s, ...)
    gfx.x, gfx.y = gfx.x / R, y
    return r
  end
end

function U.init(title, w, h, dock, x, y)
  gfx.ext_retina = 1                                   -- « je sais dessiner en haute résolution »
  gfx.init(title, w, h, dock or 0, x, y)
  wrap()
end

-- à appeler après gfx.getchar() : souris et taille de la fenêtre en points
function U.frame()
  if U.R ~= (gfx.ext_retina or 1) and (gfx.ext_retina or 1) >= 1 then wrap() end   -- fenêtre passée sur un autre écran
  local R = U.R
  U.w, U.h = gfx.w / R, gfx.h / R
  if R ~= 1 then gfx.mouse_x, gfx.mouse_y = gfx.mouse_x / R, gfx.mouse_y / R end
end
function U.W() return U.w or gfx.w end
function U.H() return U.h or gfx.h end

return U
