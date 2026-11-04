-- Podcast & ADR Toolbox.lua — la fenêtre principale : tous les outils, page par page.
-- C'est la seule action à retenir (ou à mettre dans une barre d'outils) : elle lance les autres outils.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "Toolbox_lib.lua")
local A = dofile(dir .. "Toolbox_adr.lua")

local TITLE = "Podcast & ADR Toolbox"
local SEC = P.SECTION

---------------------------------------------------------------- Lancer les autres outils
local SCRIPTS = {
  install = "Toolbox - Installation.lua", server = "Toolbox - Serveur de derushage.lua", transcribe = "Toolbox - Transcrire.lua",
  clicker = "Toolbox - Calibrer le clicker.lua", settings = "Toolbox - Reglages de transcription.lua",
  loudness = "Toolbox - Controle du niveau.lua", ripple = "Toolbox - Ripple edge.lua",
  adr_server = "Toolbox - Serveur doublage.lua", adr_vo = "Toolbox - Transcrire VO.lua", adr_srt = "Toolbox - Importer SRT.lua",
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
  { id = "cut", name = "2 · Montage" },
  { id = "voice", name = "3 · Voix" },
  { id = "export", name = "4 · Export" },
  { section = "DOUBLAGE (ADR)" },
  { id = "lines", name = "5 · Répliques" },
  { id = "rec", name = "6 · Enregistrement" },
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
  y = header(x, y, w, "Bienvenue", "Tout ce qu'il faut pour monter un podcast dans REAPER, dans l'ordre : on dérushe à partir du texte, on peaufine le montage, on soigne la voix, puis on vérifie le niveau avant d'exporter. Pour le doublage : pages Répliques et Enregistrement.")
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
    { "cut", "2 · Montage", "Ripple editing et ripple sur les bords des items." },
    { "voice", "3 · Voix", "Niveau régulier, sifflantes, plosives, équilibre." },
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
    y, p = action_row(x, y, w, "Vocal level & de-esser", "Sélectionnez les items de voix (une fois le montage terminé), puis ouvrez l'outil.", "Ouvrir", true)
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

---------------------------------------------------------------- Doublage (ADR)
local LANGS = { { "", "Langue originale" }, { "fr", "Français" }, { "en", "Anglais" }, { "it", "Italien" }, { "es", "Espagnol" } }
local adr_cache = { state = -1 }
local function adr_data()                                  -- personnages et répliques, recalculés si le projet change
  local st = reaper.GetProjectStateChangeCount(0)
  local focus = A.get("focus", "")
  if st ~= adr_cache.state or focus ~= adr_cache.focus then
    adr_cache = { state = st, focus = focus, chars = A.characters(), lines = A.lines(focus) }
  end
  return adr_cache
end

local function chip(label, x, y, color, active)
  gfx.setfont(4); local w = gfx.measurestr(label) + (color and 38 or 26)
  local over = hit(x, y, w, 28)
  col(active and COL.panel or COL.bg); gfx.rect(x, y, w, 28, 1)
  col(active and COL.accent or COL.line); gfx.rect(x, y, w, 28, 0)
  if color then gfx.set(color[1] / 255, color[2] / 255, color[3] / 255); gfx.circle(x + 14, y + 14, 5, 1, 1) end
  gfx.setfont(4); col((active or over) and COL.text or COL.muted); gfx.x, gfx.y = x + (color and 26 or 13), y + 7; gfx.drawstr(label)
  return w, clicked and over
end

local function ask_text(title, current)
  local ok, v = reaper.GetUserInputs(title, 1, "Texte de la réplique,extrawidth=420,separator=\n", current or "")
  if ok then return (v:gsub("^%s+", ""):gsub("%s+$", "")) end
end

local function page_lines(x, y, w)
  y = header(x, y, w, "Répliques", "Une réplique = un item vide sur la piste « @Personnage », le texte dans ses notes. Déplacer ou étirer l'item recale la bande rythmo. Trois façons de les créer :")
  local D = adr_data()
  local p
  -- 1. Whisper
  local target = A.get("target", "")
  y, p = action_row(x, y, w, "Depuis la VO (Whisper)", (P.settings_ok() and "" or "(Installez d'abord la transcription : page Accueil.) ") .. "Sélectionnez l'item des dialogues originaux : chaque réplique est placée sur le temps de parole. Traduction :", "Transcrire la VO", true, not P.settings_ok(),
    function(ax, ay)
      local cx = ax
      for _, L in ipairs(LANGS) do
        local cw, c = chip(L[2], cx, ay - 2, nil, target == L[1]); if c then A.set("target", L[1]) end
        cx = cx + cw + 6
      end
    end)
  y = y + 12
  if p then run(own("adr_vo")) end
  -- 2. SRT
  y, p = action_row(x, y, w, "Fichier de sous-titres (.srt)", "Une ligne « MARC: texte » va directement au personnage MARC.", "Importer un SRT")
  if p then run(own("adr_srt")) end
  -- 3. À la main
  col(COL.line); gfx.line(x, y, x + w, y)
  text("À la main", x, y + 14, COL.text, 5)
  local cur = A.get("char", "")
  local top = y
  y = wrap("Sélection temporelle sur la réplique, personnage choisi ci-dessous, puis « Nouvelle réplique ». Signes de détection à taper dans le texte : (r) respiration · (b) bouche fermée · (rire) · (s) soupir.", x, y + 38, w - 230, COL.muted, 2)
  if button("Nouvelle réplique", x + w - 210, top + 14, 210, 30, true) then
    local a, b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if b - a < 0.05 then msg = "Faites d'abord une sélection temporelle sur la réplique."
    elseif cur == "" then msg = "Choisissez d'abord un personnage (ou créez-en un) ci-dessous."
    else
      local t = ask_text("Nouvelle réplique · " .. cur)
      if t and t ~= "" then reaper.Undo_BeginBlock(); A.add_line(cur, a, b - a, t); reaper.Undo_EndBlock("Toolbox : nouvelle réplique", -1); reaper.UpdateArrange() end
    end
  end
  if button("Modifier le texte", x + w - 210, top + 50, 210, 26) then
    local sel = A.selected_lines()
    if #sel ~= 1 then msg = "Sélectionnez une seule réplique (un item sur une piste « @ »)."
    else
      local t = ask_text("Modifier la réplique", A.item_text(sel[1]))
      if t then reaper.Undo_BeginBlock(); reaper.GetSetMediaItemInfo_String(sel[1], "P_NOTES", t, true); reaper.Undo_EndBlock("Toolbox : texte de réplique", -1); reaper.UpdateArrange() end
    end
  end
  y = math.max(y + 12, top + 88)
  -- personnages
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Personnages", x, y + 14, COL.text, 5)
  local nsel = #A.selected_lines()
  local lab = (nsel > 0 and cur ~= "") and string.format("Attribuer %d réplique%s à %s", nsel, nsel > 1 and "s" or "", cur) or "Attribuer les répliques sélectionnées"
  if button(lab, x + w - 300, y + 10, 300, 28, false, false, nsel == 0 or cur == "") then
    reaper.Undo_BeginBlock(); A.assign(A.selected_lines(), cur); reaper.Undo_EndBlock("Toolbox : attribution des répliques", -1); reaper.UpdateArrange()
  end
  local cx, cy = x, y + 48
  for _, c in ipairs(D.chars) do
    local cw, cl = chip(c.name, cx, cy, c.color, cur == c.name)
    if cl then A.set("char", c.name) end
    cx = cx + cw + 6
    if cx > x + w - 140 then cx = x; cy = cy + 34 end
  end
  local _, add = chip("+ Personnage", cx, cy, nil, false)
  if add then
    local ok, v = reaper.GetUserInputs("Nouveau personnage", 1, "Nom,extrawidth=160", "")
    v = ok and v:match("^%s*(.-)%s*$") or ""
    if v ~= "" then reaper.Undo_BeginBlock(); A.char_track(v); reaper.Undo_EndBlock("Toolbox : nouveau personnage", -1); A.set("char", v); reaper.TrackList_AdjustWindows(false) end
  end
end

local tablet_url
local function adr_server_on() return is_on(own("adr_server")) end
local function ensure_adr_server() if not adr_server_on() then run(own("adr_server")) end end

function rec_go(D, i, how)
  local l = D.lines[i]; if not l then return end
  ensure_adr_server()
  local preroll = tonumber(A.get("preroll", "3")) or 3
  if reaper.GetPlayState() & 5 ~= 0 then reaper.OnStopButton() end
  reaper.Undo_BeginBlock()
  A.cue(l, preroll)
  A.set("curpos", string.format("%.3f", l.pos))
  reaper.Undo_EndBlock("Toolbox : réplique " .. i, -1)
  if how == "listen" then reaper.Main_OnCommand(1007, 0)
  elseif how == "rec" then
    local punch = A.cmd("punch"); if punch then reaper.Main_OnCommand(punch, 0) end
    reaper.Main_OnCommand(1013, 0)
  end
end

local function page_rec(x, y, w)
  y = header(x, y, w, "Enregistrement", "La bande rythmo s'affiche dans un navigateur : sur l'écran de la cabine ou sur une tablette du même réseau Wi-Fi. L'image reste dans la fenêtre vidéo de REAPER.")
  local D = adr_data()
  local on = adr_server_on()
  local port = P.web_port()
  local p
  y, p = action_row(x, y, w, "Bande rythmo", port and ("Sur la tablette (même Wi-Fi) : " .. (tablet_url or "adresse de cet ordinateur, port " .. port) .. "") or "L'interface web de REAPER n'est pas activée : Accueil › Installer / réparer.",
    "Ouvrir sur cet ordinateur", true, not port,
    function(ax, ay) status_dot(ax + 6, ay + 8, on); text(on and "Serveur de la bande actif" or "Serveur arrêté (il démarre avec la bande)", ax + 18, ay + 1, on and COL.ok or COL.muted, 2) end)
  if p then ensure_adr_server(); open_url(P.web_url("doublage.html")) end
  -- personnage
  local focus = A.get("focus", "")
  text("Personnage enregistré", x, y + 6, COL.text, 4)
  local cx = x + 180
  local cw, c = chip("Tous", cx, y, nil, focus == ""); if c then A.set("focus", "") end
  cx = cx + cw + 6
  for _, ch in ipairs(D.chars) do
    local w2, c2 = chip(ch.name, cx, y, ch.color, focus == ch.name); if c2 then A.set("focus", ch.name) end
    cx = cx + w2 + 6
  end
  y = y + 44
  -- réplique courante
  local lines = D.lines
  local i = A.current(lines) or (#lines > 0 and 1 or nil)
  col(COL.panel); gfx.rect(x, y, w, 84, 1)
  if i then
    local l = lines[i]
    gfx.set(l.char.color[1] / 255, l.char.color[2] / 255, l.char.color[3] / 255); gfx.rect(x, y, 4, 84, 1)
    local t = l.pos
    text(string.format("Réplique %d / %d  ·  %s  ·  %d:%02d:%04.1f", i, #lines, l.who:upper(), math.floor(t / 3600), math.floor(t / 60) % 60, t % 60), x + 16, y + 10, COL.muted, 4)
    wrap(l.text, x + 16, y + 32, w - 32, COL.text, 1)
  else
    wrap("Aucune réplique" .. (focus ~= "" and (" pour " .. focus) or "") .. " : créez-les dans la page « Répliques ».", x + 16, y + 30, w - 32, COL.muted, 2)
  end
  y = y + 98
  -- transport
  local bw = (w - 3 * 8) / 4
  local dis = not i
  if button("◀  Précédente", x, y, bw, 40, false, false, dis or i <= 1) then rec_go(D, i - 1) end
  if button("▶  Écouter", x + (bw + 8), y, bw, 40, false, false, dis) then rec_go(D, i, "listen") end
  local recording = reaper.GetPlayState() & 4 == 4
  if button(recording and "■  Stop" or "●  Enregistrer", x + 2 * (bw + 8), y, bw, 40, true, false, dis) then
    if recording then reaper.OnStopButton() else rec_go(D, i, "rec") end
  end
  if button("Suivante  ▶", x + 3 * (bw + 8), y, bw, 40, false, false, dis or i >= #lines) then rec_go(D, i + 1) end
  y = y + 54
  -- options
  local function toggle(label, key, def, ox)
    local v = A.get(key, def) == "1"
    local w2, c2 = chip((v and "✓ " or "") .. label, ox, y, nil, v); if c2 then A.set(key, v and "0" or "1") end
    return w2
  end
  cx = x
  cx = cx + toggle("Bips", "bips", "1", cx) + 6
  cx = cx + toggle("Boucle", "loop", "0", cx) + 6
  cx = cx + toggle("Suivante après la prise", "auto_next", "1", cx) + 18
  y = y + 38; cx = x
  text("Pré-roll", cx, y + 7, COL.muted, 2); cx = cx + 70
  local pr = A.get("preroll", "3")
  for _, v in ipairs({ "3", "4", "5", "6" }) do
    local w2, c2 = chip(v .. " s", cx, y, nil, pr == v); if c2 then A.set("preroll", v) end
    cx = cx + w2 + 4
  end
  y = y + 42
  wrap("Raccourcis : ← / → réplique précédente / suivante · R enregistrer · Espace lecture/stop. Chaque passage crée une nouvelle prise sur la piste « Prises - Personnage ».", x, y, w, COL.muted, 2)
end

local DRAW = { home = page_home, edit = page_edit, voice = page_voice, cut = page_cut, export = page_export, lines = page_lines, rec = page_rec }


local function draw()
  local w, h = gfx.w, gfx.h
  col(COL.bg); gfx.rect(0, 0, w, h, 1)
  local sw = 190
  col(COL.side); gfx.rect(0, 0, sw, h, 1)
  text("Podcast &", 22, 18, COL.text, 3)
  text("ADR Toolbox", 22, 42, COL.text, 3)
  local y = 84
  for _, pg in ipairs(PAGES) do
    if pg.section then
      y = y + 10
      text(pg.section, 22, y + 4, COL.muted, 4)
      y = y + 26
      goto continue
    end
    local act = page == pg.id
    local over = hit(0, y, sw, 38)
    if act then col(COL.panel); gfx.rect(0, y, sw, 38, 1); col(COL.accent); gfx.rect(0, y, 4, 38, 1)
    elseif over then col(COL.panel, 0.5); gfx.rect(0, y, sw, 38, 1) end
    text(pg.name, 22, y + 11, act and COL.text or COL.muted, act and 4 or 1)
    if clicked and over then go(pg.id) end
    y = y + 40
    ::continue::
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
  if page == "rec" and (ch == 1818584692 or ch == 1919379572 or ch == 114 or ch == 82) then   -- ← → R
    local D = adr_data()
    local i = A.current(D.lines) or 1
    if ch == 1818584692 then rec_go(D, math.max(1, i - 1))
    elseif ch == 1919379572 then rec_go(D, math.min(#D.lines, i + 1))
    elseif reaper.GetPlayState() & 4 == 0 then rec_go(D, i, "rec") end
  end
  if reaper.GetExtState(A.SEC, "just_recorded") == "1" then          -- prise terminée : réplique suivante
    reaper.DeleteExtState(A.SEC, "just_recorded", false)
    if A.get("auto_next", "1") == "1" then
      local D = adr_data(); local i = A.current(D.lines)
      if i and i < #D.lines then rec_go(D, i + 1) end
    end
  end
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
do local ip, port = A.lan_ip(), P.web_port(); if ip and port then tablet_url = "http://" .. ip .. ":" .. port .. "/doublage.html" end end
if not DRAW[page] then page = "home" end
loop()
