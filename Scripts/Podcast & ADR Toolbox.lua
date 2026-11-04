-- Podcast & ADR Toolbox.lua — la fenêtre principale : tous les outils, page par page.
-- C'est la seule action à retenir (ou à mettre dans une barre d'outils) : elle lance les autres outils.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "Toolbox_lib.lua")

local TITLE = "Podcast & ADR Toolbox"
local SEC = P.SECTION

---------------------------------------------------------------- Lancer les autres outils
local SCRIPTS = {
  install = "Toolbox - Installation.lua", server = "Toolbox - Serveur de derushage.lua", transcribe = "Toolbox - Transcrire.lua",
  clicker = "Toolbox - Calibrer le clicker.lua", settings = "Toolbox - Reglages de transcription.lua",
  loudness = "Toolbox - Controle du niveau.lua", ripple = "Toolbox - Ripple edge.lua",
}
local cmd_cache = {}
local function cmd_of(path)
  if not path then return nil end
  if cmd_cache[path] == nil then
    local c = P.exists(path) and reaper.AddRemoveReaScript(true, 0, path, true) or 0
    cmd_cache[path] = c
  end
  return cmd_cache[path] > 0 and cmd_cache[path] or nil
end
local function run(path) local c = cmd_of(path); if c then reaper.Main_OnCommand(c, 0); return true end end
local function is_on(path) local c = cmd_of(path); return c and reaper.GetToggleCommandState(c) == 1 end
local function own(k) return dir .. SCRIPTS[k] end

-- Vocal level & de-esser (autre dépôt) : on cherche le script dans le dossier Scripts de REAPER
local vocal_path
local function find_vocal()
  if P.exists(dir .. "Vocal level & de-esser.lua") then return dir .. "Vocal level & de-esser.lua" end   -- livré dans la boîte à outils
  local saved = reaper.GetExtState(SEC, "vocal_path")
  if saved ~= "" and P.exists(saved) then return saved end
  local root = reaper.GetResourcePath() .. P.SEP .. "Scripts"
  local function scan(d, depth)
    local i = 0
    while true do
      local f = reaper.EnumerateFiles(d, i); if not f then break end
      if f == "Vocal level & de-esser.lua" then return d .. P.SEP .. f end
      i = i + 1
    end
    if depth >= 3 then return end
    i = 0
    while true do
      local s = reaper.EnumerateSubdirectories(d, i); if not s then break end
      local r = scan(d .. P.SEP .. s, depth + 1); if r then return r end
      i = i + 1
    end
  end
  local r = scan(root, 0)
  if r then reaper.SetExtState(SEC, "vocal_path", r, true) end
  return r
end

local function open_url(u)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(u); return end
  if P.WIN then os.execute('start "" "' .. u .. '"')
  elseif reaper.GetOS():find("OSX") or reaper.GetOS():find("mac") then os.execute('open "' .. u .. '"')
  else os.execute('xdg-open "' .. u .. '"') end
end

---------------------------------------------------------------- Ripple de REAPER (actions retrouvées par leur nom)
local RIPPLE = {}
local SNAP = {}                          -- toggle = aimantation générale, items = aimantation aux bords des items
local function find_ripple_cmds()
  local ok = true
  for _, k in ipairs({ "off", "track", "all" }) do
    local id = tonumber(reaper.GetExtState(SEC, "ripple_cmd_" .. k))
    if id then RIPPLE[k] = id else ok = false end
  end
  for _, k in ipairs({ "toggle", "items" }) do
    local id = tonumber(reaper.GetExtState(SEC, "snap_cmd_" .. k))
    if id and id > 0 then SNAP[k] = id end
  end
  if reaper.GetExtState(SEC, "cmd_scan") == "2" and ok then return end
  if not reaper.kbd_getTextFromCmd then return end
  for id = 1, 45000 do
    local okc, name = pcall(reaper.kbd_getTextFromCmd, id, 0)
    if okc and type(name) == "string" and name ~= "" then
      local n = name:lower()
      if n:find("ripple editing", 1, true) and not n:find("toggle", 1, true) and not n:find("cycle", 1, true) then
        local k = (n:find("per%-track") or n:find("per track")) and "track" or n:find("all tracks", 1, true) and "all" or n:find("off", 1, true) and "off"
        if k and not RIPPLE[k] then RIPPLE[k] = id; reaper.SetExtState(SEC, "ripple_cmd_" .. k, tostring(id), true) end
      elseif n == "options: toggle snapping" and not SNAP.toggle then
        SNAP.toggle = id
      elseif n:find("toggle", 1, true) and n:find("snap", 1, true) and (n:find("item edge", 1, true) or n:find("media item", 1, true))
          and not n:find("grid", 1, true) and not n:find("midi", 1, true) and not SNAP.items then
        SNAP.items = id
      end
    end
  end
  reaper.SetExtState(SEC, "snap_cmd_toggle", tostring(SNAP.toggle or 0), true)
  reaper.SetExtState(SEC, "snap_cmd_items", tostring(SNAP.items or 0), true)
  reaper.SetExtState(SEC, "cmd_scan", "2", true)
end
local function snap_on()
  return SNAP.toggle and reaper.GetToggleCommandState(SNAP.toggle) == 1
    and (not SNAP.items or reaper.GetToggleCommandState(SNAP.items) == 1)
end
local function set_snap(on)
  if SNAP.toggle and (reaper.GetToggleCommandState(SNAP.toggle) == 1) ~= on then reaper.Main_OnCommand(SNAP.toggle, 0) end
  if on and SNAP.items and reaper.GetToggleCommandState(SNAP.items) ~= 1 then reaper.Main_OnCommand(SNAP.items, 0) end
end
local function ripple_mode()
  if RIPPLE.all and reaper.GetToggleCommandState(RIPPLE.all) == 1 then return "all" end
  if RIPPLE.track and reaper.GetToggleCommandState(RIPPLE.track) == 1 then return "track" end
  return "off"
end

---------------------------------------------------------------- Interface
local W, H = 860, 600
local dock = tonumber(reaper.GetExtState(SEC, "hub_dock")) or 0
gfx.init(TITLE, W, H, dock)
local COL = {
  bg = { 0.10, 0.105, 0.12 }, side = { 0.075, 0.08, 0.09 }, panel = { 0.14, 0.15, 0.17 }, text = { 0.93, 0.93, 0.93 },
  muted = { 0.6, 0.62, 0.67 }, accent = { 0.97, 0.6, 0.22 }, line = { 0.24, 0.25, 0.28 }, ok = { 0.3, 0.8, 0.5 }, bad = { 0.95, 0.42, 0.32 },
}
local function col(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function fonts()
  gfx.setfont(1, "Arial", 15); gfx.setfont(2, "Arial", 13); gfx.setfont(3, "Arial", 21, string.byte("b"))
  gfx.setfont(4, "Arial", 14, string.byte("b")); gfx.setfont(5, "Arial", 16, string.byte("b"))
end
fonts()
local function text(s, x, y, c, f) gfx.setfont(f or 1); col(c or COL.text); gfx.x, gfx.y = x, y; gfx.drawstr(s) end
local function wrap(s, x, y, w, c, f)
  gfx.setfont(f or 2); col(c or COL.text)
  local line, lh = "", gfx.texth + 3
  for word in s:gmatch("%S+") do
    local t = line == "" and word or (line .. " " .. word)
    if gfx.measurestr(t) > w and line ~= "" then gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh; line = word else line = t end
  end
  if line ~= "" then gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh end
  return y
end
local function hit(x, y, w, h) return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h end
local clicked, mouse_was = false, false
local function button(label, x, y, w, h, primary, active, disabled)
  local over = hit(x, y, w, h) and not disabled
  if disabled then col(COL.panel, 0.6) elseif primary or active then col(COL.accent, over and 1 or 0.88) else col(COL.panel) end
  gfx.rect(x, y, w, h, 1)
  if not (primary or active) then col(COL.line); gfx.rect(x, y, w, h, 0) end
  gfx.setfont(4); local tw = gfx.measurestr(label)
  if disabled then col(COL.muted) elseif primary or active then gfx.set(0.1, 0.06, 0.02) else col(COL.text) end
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - gfx.texth) / 2; gfx.drawstr(label)
  return clicked and over
end
local function status_dot(x, y, ok)
  col(ok and COL.ok or COL.bad); gfx.circle(x, y, 5, 1, 1)
end

local PAGES = {
  { id = "home", name = "Accueil" },
  { id = "edit", name = "1 · Dérushage" },
  { id = "voice", name = "2 · Voix" },
  { id = "cut", name = "3 · Montage" },
  { id = "export", name = "4 · Export" },
}
local page = reaper.GetExtState(SEC, "hub_page"); if page == "" then page = "home" end
local msg = ""
local function go(id) page = id; reaper.SetExtState(SEC, "hub_page", id, true); msg = "" end

---------------------------------------------------------------- Pages
local function header(x, y, w, title, sub)
  text(title, x, y, COL.text, 3)
  return wrap(sub, x, y + 32, w, COL.muted, 2) + 14
end

-- une ligne d'action : titre, explication, bouton à droite ; renvoie la nouvelle position et l'état du clic
local function action_row(x, y, w, title, desc, label, primary, disabled, extra)
  col(COL.line); gfx.line(x, y, x + w, y)
  text(title, x, y + 14, COL.text, 5)
  local bw = 210
  local ny = wrap(desc, x, y + 38, w - bw - 24, COL.muted, 2)
  if extra then extra(x, ny) ; ny = ny + 22 end
  local pressed = button(label, x + w - bw, y + 16, bw, 34, primary, false, disabled)
  return math.max(ny + 12, y + 66), pressed
end

local function page_home(x, y, w)
  y = header(x, y, w, "Bienvenue", "Tout ce qu'il faut pour monter un podcast dans REAPER, dans l'ordre : on dérushe à partir du texte, on soigne la voix, on peaufine le montage, puis on vérifie le niveau avant d'exporter.")
  -- état de l'installation
  local whisper_ok = P.settings_ok()
  local web_ok = P.web_port() ~= nil
  local vocal_ok = vocal_path ~= nil
  local rows = {
    { whisper_ok and web_ok, "Transcription (Whisper) et interface web", whisper_ok and web_ok and "prêtes" or "à installer une fois" },
    { vocal_ok, "Vocal level & de-esser", vocal_ok and "installé" or "introuvable (synchronisez ReaPack)" },
  }
  col(COL.panel); gfx.rect(x, y, w, 26 + #rows * 26, 1)
  text("INSTALLATION", x + 14, y + 8, COL.muted, 4)
  local ry = y + 30
  for _, r in ipairs(rows) do
    status_dot(x + 20, ry + 8, r[1]); text(r[2], x + 34, ry, COL.text, 2); text(r[3], x + 360, ry, r[1] and COL.ok or COL.bad, 2)
    ry = ry + 26
  end
  if not (whisper_ok and web_ok) then
    if button("Installer / réparer", x + w - 190, y + 4, 176, 24, true) then run(own("install")) end
  end
  y = y + 26 + #rows * 26 + 20
  text("LE PARCOURS", x, y, COL.muted, 4)
  y = y + 24
  local cw = (w - 3 * 12) / 4
  local cards = {
    { "edit", "1 · Dérushage", "Transcrire, barrer les passages à couper dans le texte." },
    { "voice", "2 · Voix", "Niveau régulier, sifflantes, plosives, équilibre." },
    { "cut", "3 · Montage", "Ripple editing et ripple sur les bords des items." },
    { "export", "4 · Export", "Vérifier la norme (LUFS, true peak), puis exporter." },
  }
  for i, c in ipairs(cards) do
    local cx = x + (i - 1) * (cw + 12)
    local over = hit(cx, y, cw, 120)
    col(COL.panel, over and 1 or 0.85); gfx.rect(cx, y, cw, 120, 1)
    col(COL.accent); gfx.rect(cx, y, cw, 3, 1)
    text(c[2], cx + 12, y + 14, COL.text, 5)
    wrap(c[3], cx + 12, y + 42, cw - 24, COL.muted, 2)
    if clicked and over then go(c[1]) end
  end
  y = y + 140
  wrap("Astuce : mettez l'action « Podcast & ADR Toolbox » dans une barre d'outils (clic droit sur la barre › Personnaliser) ; c'est la seule à retenir. Le bouton « Ancrer » en bas à gauche place cette fenêtre dans REAPER.", x, y, w, COL.muted, 2)
end

local function page_edit(x, y, w)
  y = header(x, y, w, "Dérushage", "Whisper écrit tout ce qui a été dit ; dans la page de dérushage, vous barrez ce qu'il faut couper. Les coupes vous sont suggérées, rien n'est coupé sans votre accord.")
  local server_on = is_on(own("server"))
  local p
  y, p = action_row(x, y, w, "Transcrire", "Sélectionnez les pistes des micros (ou les items), puis lancez la transcription. Cela peut prendre quelques minutes.", "Transcrire la sélection", true)
  if p then run(own("transcribe")) end
  y, p = action_row(x, y, w, "Page de dérushage", "Ouvre la page dans votre navigateur. Le montage se construit dans REAPER au fur et à mesure (pistes « ✂ »).", "Ouvrir la page", true, false,
    function(ax, ay) status_dot(ax + 6, ay + 8, server_on); text(server_on and "Lien avec REAPER actif" or "Lien avec REAPER arrêté (il démarre avec la page)", ax + 18, ay + 1, server_on and COL.ok or COL.muted, 2) end)
  if p then
    if not P.web_port() then msg = "L'interface web de REAPER n'est pas activée : page Accueil › Installer / réparer."
    else
      if not server_on then run(own("server")) end
      open_url(P.web_url())
    end
  end
  if server_on then
    if button("Arrêter le lien", x + w - 210, y - 14, 210, 26) then reaper.SetExtState(SEC, "stop_server", "1", false) end
    y = y + 20
  end
  y, p = action_row(x, y, w, "Calibrer le clicker", "Placez le curseur juste avant un clic sur la piste du micro : l'outil apprend le son de votre clicker.", "Calibrer")
  if p then run(own("clicker")) end
  y, p = action_row(x, y, w, "Réglages de transcription", "Emplacement de Whisper, modèle, langue, vocabulaire.", "Réglages")
  if p then run(own("settings")) end
end

local function page_voice(x, y, w)
  y = header(x, y, w, "Voix", "Vocal level & de-esser rend la voix plus régulière et plus propre : niveau, sifflantes, plosives, voix trop proche du micro, équilibre tonal. Il dessine des courbes sur les items, rien n'est figé.")
  local p
  if vocal_path then
    y, p = action_row(x, y, w, "Vocal level & de-esser", "Sélectionnez les items de voix (après le dérushage), puis ouvrez l'outil.", "Ouvrir", true)
    if p then run(vocal_path) end
  else
    col(COL.panel); gfx.rect(x, y, w, 96, 1)
    text("Outil introuvable", x + 16, y + 14, COL.text, 5)
    wrap("Mettez la boîte à outils à jour : Extensions › ReaPack › Synchronize packages.", x + 16, y + 40, w - 220, COL.muted, 2)
    if button("Vérifier à nouveau", x + w - 176, y + 56, 160, 26) then reaper.DeleteExtState(SEC, "vocal_path", true); vocal_path = find_vocal(); msg = vocal_path and "Trouvé !" or "Toujours introuvable." end
  end
end

local function page_cut(x, y, w)
  y = header(x, y, w, "Montage", "Le ripple editing fait suivre la suite du montage quand on supprime ou déplace un item. La boîte à outils ajoute le ripple sur les bords, et l'aimantation garde les items collés les uns aux autres.")
  -- aimantation
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Aimantation des items (snap)", x, y + 14, COL.text, 5)
  if SNAP.toggle then
    local on = snap_on()
    if button(on and "Activée" or "Désactivée", x + w - 150, y + 12, 150, 30, false, on) then set_snap(not on) end
    y = wrap("Quand on déplace un item ou qu'on tire un de ses bords, il se colle au bord des items voisins.", x, y + 48, w - 180, COL.muted, 2) + 16
  else
    y = wrap("Activez l'aimant de la barre d'outils de REAPER (clic droit dessus pour cocher l'aimantation aux items).", x, y + 48, w, COL.muted, 2) + 16
  end
  -- ripple de REAPER
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Ripple editing de REAPER", x, y + 14, COL.text, 5)
  local mode = ripple_mode()
  local bw = 160
  if RIPPLE.off and RIPPLE.track and RIPPLE.all then
    for i, b in ipairs({ { "off", "Désactivé" }, { "track", "Par piste" }, { "all", "Toutes les pistes" } }) do
      if button(b[2], x + (i - 1) * (bw + 6), y + 42, bw, 30, false, mode == b[1]) then reaper.Main_OnCommand(RIPPLE[b[1]], 0) end
    end
  else
    text("(utilisez le bouton ripple de la barre d'outils de REAPER)", x, y + 48, COL.muted, 2)
  end
  y = y + 36
  y = wrap("Par piste : seule la piste modifiée se décale. Toutes les pistes : tout le projet suit (pratique pour garder les intervenants synchronisés).", x, y + 48, w - 24, COL.muted, 2) + 16
  -- ripple sur les bords
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Ripple sur les bords des items", x, y + 14, COL.text, 5)
  local on = is_on(own("ripple"))
  if button(on and "Activé" or "Désactivé", x + w - 150, y + 12, 150, 30, false, on) then
    if on then reaper.SetExtState(SEC, "ripple_stop", "1", false) else run(own("ripple")) end
  end
  y = wrap("Pendant que vous tirez un bord, les voisins se décalent en direct, de la même valeur : bord droit, tout ce qui suit ; bord gauche, tout ce qui précède. Aucun fondu n'est ajouté. Même portée que le ripple de REAPER (la piste, ou toutes les pistes).", x, y + 48, w - 24, COL.muted, 2) + 10
end

local function page_export(x, y, w)
  y = header(x, y, w, "Export", "Avant d'exporter, vérifiez que le niveau respecte la norme de la plateforme : Podcast (−16 LUFS) ou Spotify (−14 LUFS), true peak max −1 dBTP. L'outil explique quoi corriger et peut corriger automatiquement.")
  local p
  y, p = action_row(x, y, w, "Contrôle du niveau", "Mesure le mix du master sans exporter, compare à la norme et propose des corrections.", "Vérifier le niveau", true)
  if p then run(own("loudness")) end
  y, p = action_row(x, y, w, "Exporter", "Ouvre la fenêtre de rendu de REAPER. Si le niveau a été vérifié, ne cochez pas de normalisation.", "Ouvrir l'export")
  if p then reaper.Main_OnCommand(40015, 0) end
end

local DRAW = { home = page_home, edit = page_edit, voice = page_voice, cut = page_cut, export = page_export }

local function draw()
  local w, h = gfx.w, gfx.h
  col(COL.bg); gfx.rect(0, 0, w, h, 1)
  local sw = 190
  col(COL.side); gfx.rect(0, 0, sw, h, 1)
  text("Podcast &", 22, 18, COL.text, 3)
  text("ADR Toolbox", 22, 42, COL.text, 3)
  local y = 84
  for _, pg in ipairs(PAGES) do
    local act = page == pg.id
    local over = hit(0, y, sw, 38)
    if act then col(COL.panel); gfx.rect(0, y, sw, 38, 1); col(COL.accent); gfx.rect(0, y, 4, 38, 1)
    elseif over then col(COL.panel, 0.5); gfx.rect(0, y, sw, 38, 1) end
    text(pg.name, 22, y + 11, act and COL.text or COL.muted, act and 4 or 1)
    if clicked and over then go(pg.id) end
    y = y + 40
  end
  local d = gfx.dock(-1) & 1 == 1
  if button(d and "Détacher" or "Ancrer", 16, h - 50, sw - 32, 30) then
    gfx.dock(d and 0 or 1)
    reaper.SetExtState(SEC, "hub_dock", tostring(gfx.dock(-1)), true)
  end
  local cx, cw = sw + 32, math.max(300, w - sw - 64)
  DRAW[page](cx, 26, cw)
  if msg ~= "" then wrap(msg, cx, h - 30, cw, COL.accent, 2) end
  gfx.update()
end

local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then return end
  local cap = gfx.mouse_cap
  if ch == 32 then reaper.Main_OnCommand(40044, 0)
  elseif ch == 26 or (ch == 122 and cap & 4 == 4) then reaper.Main_OnCommand(cap & 8 == 8 and 40030 or 40029, 0)
  elseif ch == 25 or (ch == 121 and cap & 4 == 4) then reaper.Main_OnCommand(40030, 0) end
  local down = cap & 1 == 1
  clicked = down and not mouse_was
  mouse_was = down
  draw()
  reaper.defer(loop)
end

find_ripple_cmds()
if reaper.GetExtState(SEC, "snap_default") ~= "1" then          -- par défaut : items aimantés les uns aux autres
  set_snap(true); reaper.SetExtState(SEC, "snap_default", "1", true)
end
vocal_path = find_vocal()
if not DRAW[page] then page = "home" end
loop()
