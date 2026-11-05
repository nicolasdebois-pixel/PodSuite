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
local SNAP = {}                          -- toggle = aimantation générale, items = aux bords des items, grid = à la grille
local META                               -- fenêtre des métadonnées de rendu (tags ID3)
local function find_ripple_cmds()
  local ok = true
  for _, k in ipairs({ "off", "track", "all" }) do
    local id = tonumber(reaper.GetExtState(SEC, "ripple_cmd_" .. k))
    if id then RIPPLE[k] = id else ok = false end
  end
  for _, k in ipairs({ "toggle", "items", "grid" }) do
    local id = tonumber(reaper.GetExtState(SEC, "snap_cmd_" .. k))
    if id and id > 0 then SNAP[k] = id end
  end
  META = tonumber(reaper.GetExtState(SEC, "meta_cmd")); if META == 0 then META = nil end
  if reaper.GetExtState(SEC, "cmd_scan") == "3" and ok then return end
  if not reaper.kbd_getTextFromCmd then return end
  for id = 1, 65000 do
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
      elseif n:find("toggle", 1, true) and n:find("snap", 1, true) and n:find("grid", 1, true) and not SNAP.grid
          and not (n:find("midi", 1, true) or n:find("relative", 1, true) or n:find("frame", 1, true) or n:find("line", 1, true)
            or n:find("show", 1, true) or n:find("visible", 1, true) or n:find("division", 1, true) or n:find("swing", 1, true)) then
        SNAP.grid = id
      elseif n:find("metadata", 1, true) and (n:find("render", 1, true) or n:find("project", 1, true))
          and not (n:find("item", 1, true) or n:find("marker", 1, true) or n:find("take", 1, true) or n:find("region", 1, true)) and not META then
        META = id
      end
    end
  end
  reaper.SetExtState(SEC, "snap_cmd_toggle", tostring(SNAP.toggle or 0), true)
  reaper.SetExtState(SEC, "snap_cmd_items", tostring(SNAP.items or 0), true)
  reaper.SetExtState(SEC, "snap_cmd_grid", tostring(SNAP.grid or 0), true)
  reaper.SetExtState(SEC, "meta_cmd", tostring(META or 0), true)
  reaper.SetExtState(SEC, "cmd_scan", "3", true)
end
local function snap_on()
  return SNAP.toggle and reaper.GetToggleCommandState(SNAP.toggle) == 1
    and (not SNAP.items or reaper.GetToggleCommandState(SNAP.items) == 1)
end
local function set_snap(on)
  if SNAP.toggle and (reaper.GetToggleCommandState(SNAP.toggle) == 1) ~= on then reaper.Main_OnCommand(SNAP.toggle, 0) end
  if on and SNAP.items and reaper.GetToggleCommandState(SNAP.items) ~= 1 then reaper.Main_OnCommand(SNAP.items, 0) end
  -- aux bords des items seulement : pas à la grille (sinon les items sautent de division en division)
  if on and SNAP.grid and reaper.GetToggleCommandState(SNAP.grid) == 1 then reaper.Main_OnCommand(SNAP.grid, 0) end
end
local function ripple_mode()
  if RIPPLE.all and reaper.GetToggleCommandState(RIPPLE.all) == 1 then return "all" end
  if RIPPLE.track and reaper.GetToggleCommandState(RIPPLE.track) == 1 then return "track" end
  return "off"
end

---------------------------------------------------------------- Interface
local W, H = 860, 680
local dock = 0                                               -- fenêtre flottante (trop grande pour être ancrée)
local U = dofile(dir .. "Toolbox_ui.lua")
U.init(TITLE, W, H, dock)
local COL = {
  bg = { 0.10, 0.105, 0.12 }, side = { 0.075, 0.08, 0.09 }, panel = { 0.14, 0.15, 0.17 }, text = { 0.93, 0.93, 0.93 },
  muted = { 0.6, 0.62, 0.67 }, accent = { 0.97, 0.6, 0.22 }, line = { 0.24, 0.25, 0.28 }, ok = { 0.3, 0.8, 0.5 }, bad = { 0.95, 0.42, 0.32 },
}
local function col(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function fonts()
  gfx.setfont(1, "Arial", 16); gfx.setfont(2, "Arial", 14); gfx.setfont(3, "Arial", 22, string.byte("b"))
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
local function button(label, x, y, w, h, primary, active, disabled, color)
  local over = hit(x, y, w, h) and not disabled
  if disabled then col(COL.panel, 0.6) elseif color then col(color, over and 1 or 0.85) elseif primary or active then col(COL.accent, over and 1 or 0.88) else col(COL.panel) end
  gfx.rect(x, y, w, h, 1)
  if not (primary or active or color) then col(COL.line); gfx.rect(x, y, w, h, 0) end
  gfx.setfont(4); local tw = gfx.measurestr(label)
  if disabled then col(COL.muted) elseif color then gfx.set(1, 1, 1) elseif primary or active then gfx.set(0.1, 0.06, 0.02) else col(COL.text) end
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - gfx.texth) / 2; gfx.drawstr(label)
  return clicked and over
end
local function status_dot(x, y, ok)
  col(ok and COL.ok or COL.bad); gfx.circle(x, y, 5, 1, 1)
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

local PAGES = {
  { id = "home", name = "Accueil" },
  { id = "edit", name = "1 · Dérushage", use = "podcast" },
  { id = "cut", name = "2 · Édition" },
  { id = "voice", name = "3 · Voix" },
  { id = "export", name = "4 · Export" },
  { section = "DOUBLAGE (ADR)", use = "adr" },
  { id = "lines", name = "5 · Répliques", use = "adr" },
  { id = "rec", name = "6 · Enregistrement", use = "adr" },
}
local function usage() return "both" end                     -- toutes les pages sont affichées
local function shown(pg) return true end
local page = reaper.GetExtState(SEC, "hub_page"); if page == "" then page = "home" end
local function expert() return true end                    -- tous les réglages sont toujours affichés
local msg = ""
-- le doublage passe REAPER en « auto-punch » : on remet le mode normal dès qu'on quitte la page Enregistrement
local function restore_record_mode()
  if reaper.GetExtState(A.SEC, "punch_on") == "1" then
    local n = A.cmd("normal"); if n then reaper.Main_OnCommand(n, 0) end
    reaper.DeleteExtState(A.SEC, "punch_on", false)
  end
end
local function go(id)
  if page == "rec" and id ~= "rec" then restore_record_mode() end
  page = id; reaper.SetExtState(SEC, "hub_page", id, true); msg = ""
end

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

-- projets d'exercice : adresses dans Toolbox_demo.json (modifiable par l'enseignant dans le dépôt)
local DEMO = (function()
  local ok, d = pcall(P.json_decode, P.read_file(dir .. "Toolbox_demo.json") or "")
  return ok and type(d) == "table" and d or {}
end)()
local demo_job
local function demo_start(key)
  local d = DEMO[key]; if not d or not d.url or d.url == "" then return end
  local base = P.RES .. P.SEP .. "exercices" .. P.SEP .. key
  reaper.RecursiveCreateDirectory(base, 0)
  local zip, st = base .. ".zip", base .. ".status"
  os.remove(st)
  local function q(x) return '"' .. x .. '"' end
  local cmd
  if P.WIN then
    cmd = 'cmd.exe /C "curl.exe -L --fail -sS -o ' .. q(zip) .. " " .. q(d.url) .. " && tar.exe -xf " .. q(zip) .. " -C " .. q(base) .. " && (echo ok>" .. q(st) .. ") || (echo fail>" .. q(st) .. ')"'
  else
    local sh = "/usr/bin/curl -L --fail -sS -o " .. q(zip) .. " " .. q(d.url) .. " && /usr/bin/unzip -oq " .. q(zip) .. " -d " .. q(base) ..
      " && echo ok > " .. q(st) .. " || echo fail > " .. q(st)
    cmd = "/bin/sh -c '" .. sh:gsub("'", "'\\''") .. "'"
  end
  reaper.ExecProcess(cmd, -1)
  demo_job = { key = key, base = base, st = st, t0 = reaper.time_precise() }
end
local function find_rpp(root, depth)
  depth = depth or 0
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(root, i); if not f then break end
    if f:lower():match("%.rpp$") then return root .. P.SEP .. f end
    i = i + 1
  end
  if depth >= 3 then return end
  i = 0
  while true do
    local d = reaper.EnumerateSubdirectories(root, i); if not d then break end
    if not d:match("^__MACOSX") then local r = find_rpp(root .. P.SEP .. d, depth + 1); if r then return r end end
    i = i + 1
  end
end
local function demo_poll()
  if not demo_job then return end
  local r = P.read_file(demo_job.st)
  if r and r:find("ok") then
    local rpp = find_rpp(demo_job.base)
    demo_job = nil
    if rpp then reaper.Main_openProject(rpp); msg = "Projet d'exercice ouvert. Enregistrez-le sous un autre nom (Fichier › Enregistrer sous) pour garder l'original intact."
    else msg = "Téléchargé, mais aucun projet REAPER (.rpp) dans l'archive." end
  elseif r and r:find("fail") then demo_job = nil; msg = "Téléchargement du projet d'exercice impossible (connexion internet ?)."
  end
end

local function page_home(x, y, w)
  y = header(x, y, w, "Bienvenue", "Tout ce qu'il faut pour monter un podcast dans REAPER, dans l'ordre : on dérushe à partir du texte, on peaufine le montage avec les outils d'édition, on soigne la voix, puis on vérifie le niveau avant d'exporter. Pour le doublage : pages Répliques et Enregistrement.")
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
    { "cut", "2 · Édition", "Comportement des outils : ripple, bords des items, aimantation." },
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
  do                                                          -- doublage : les deux pages
    y = y + 132
    for i, c in ipairs({ { "lines", "5 · Répliques", "Depuis la VO, un SRT ou à la main." }, { "rec", "6 · Enregistrement", "Bande rythmo en cabine, prises, bips." } }) do
      local cx = x + (i - 1) * (cw + 12)
      local over = hit(cx, y, cw, 108)
      col(COL.panel, over and 1 or 0.85); gfx.rect(cx, y, cw, 108, 1)
      col(COL.ok); gfx.rect(cx, y, cw, 3, 1)
      text(c[2], cx + 12, y + 14, COL.text, 5)
      wrap(c[3], cx + 12, y + 42, cw - 24, COL.muted, 2)
      if clicked and over then go(c[1]) end
    end
    y = y - 132 + 120
  end
  y = y + 140
  -- projets d'exercice (si l'enseignant en a publié)
  local any = false
  for _, k in ipairs({ "podcast", "doublage" }) do if DEMO[k] and DEMO[k].url and DEMO[k].url ~= "" then any = true end end
  if any then
    text("S'EXERCER", x, y, COL.muted, 4)
    y = y + 22
    local bx = x
    for _, k in ipairs({ "podcast", "doublage" }) do
      local d = DEMO[k]
      if d and d.url and d.url ~= "" then
        local lab = demo_job and demo_job.key == k and string.format("Téléchargement… %d s", math.floor(reaper.time_precise() - demo_job.t0)) or (d.title or ("Projet d'exercice : " .. k))
        gfx.setfont(4); local bw = gfx.measurestr(lab) + 40
        if button(lab, bx, y, bw, 32, false, false, demo_job ~= nil) then demo_start(k) end
        bx = bx + bw + 8
      end
    end
    y = y + 46
  end
  y = wrap("Astuce : mettez l'action « Podcast & ADR Toolbox » dans une barre d'outils (clic droit sur la barre › Personnaliser) ; c'est la seule à retenir.", x, y, w, COL.muted, 2)
  return y + 20
end

---------------------------------------------------------------- Exports du dérushage : texte, sous-titres, chapitres
-- Le texte suit le MONTAGE : les mots barrés disparaissent et les temps sont ceux de la version montée.
local ACC_UP = { ["à"] = "À", ["â"] = "Â", ["ä"] = "Ä", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë", ["î"] = "Î", ["ï"] = "Ï",
  ["ô"] = "Ô", ["ö"] = "Ö", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ç"] = "Ç", ["ñ"] = "Ñ" }
local function upper(s) return (s:upper():gsub("[\xC3][\x80-\xBF]", function(c) return ACC_UP[c] or c end)) end
local function tc_srt(t)
  t = math.max(0, t)
  local ms = math.floor(t * 1000 + 0.5)
  return string.format("%02d:%02d:%02d,%03d", ms // 3600000, (ms // 60000) % 60, (ms // 1000) % 60, ms % 1000)
end
local function tc_chap(t)
  t = math.max(0, math.floor(t + 0.5))
  if t >= 3600 then return string.format("%d:%02d:%02d", t // 3600, (t // 60) % 60, t % 60) end
  return string.format("%02d:%02d", t // 60, t % 60)
end

-- mots gardés, avec leur temps dans le montage ; nil + message si pas de transcription
local function kept_words()
  local _, fn, ddir, name = P.project()
  if not fn then return nil, "Enregistrez d'abord le projet." end
  local ok, data = pcall(P.json_decode, P.read_file(ddir .. P.SEP .. "transcript.json") or "")
  if not ok or type(data) ~= "table" or not data.words then return nil, "Pas encore de transcription pour ce projet (page Dérushage › Transcrire)." end
  local struck = {}
  for _, r in ipairs((data.edits or {}).strikes or {}) do for i = r[1] + 1, r[2] + 1 do struck[i] = true end end
  local segs
  local okm, map = pcall(P.json_decode, P.read_file(P.www_dir() .. P.SEP .. "podsuite_map.json") or "")
  if okm and type(map) == "table" and type(map.segs) == "table" and #map.segs > 0 and next(struck) then segs = map.segs end
  local function remap(t)
    if not segs then return t end
    for _, s in ipairs(segs) do if t >= s[1] - 0.005 and t < s[2] + 0.005 then return s[3] + (t - s[1]) end end
  end
  local out = {}
  for i, w in ipairs(data.words) do
    if not struck[i] and not w.gap and w.w and w.w ~= "" then
      local a, b = remap(w.a), remap(w.b)
      if a then
        local sp = data.speakers and data.speakers[w.s or 0]
        out[#out + 1] = { w = w.w, a = a, b = b or (a + 0.2), who = sp and sp.name or "" }
      end
    end
  end
  return out, nil, ddir:gsub("[/\\]PodSuite$", ""):gsub("[/\\]Transcription$", ""), name
end

local function save_text(path, s)
  if not P.write_file(path, s) then return false end
  return true
end

local function export_transcript(kind)
  local words, err, folder, name = kept_words()
  if not words then msg = err; return end
  if #words == 0 then msg = "Aucun mot à exporter."; return end
  local path
  if kind == "txt" then
    local paras, cur, who = {}, {}, nil
    for i, w in ipairs(words) do
      local gap = i > 1 and (w.a - words[i - 1].b) or 0
      if w.who ~= who or gap > 2.5 then
        if #cur > 0 then paras[#paras + 1] = (who and who ~= "" and (upper(who) .. " : ") or "") .. table.concat(cur, " ") end
        cur, who = {}, w.who
      end
      cur[#cur + 1] = w.w
    end
    if #cur > 0 then paras[#paras + 1] = (who and who ~= "" and (upper(who) .. " : ") or "") .. table.concat(cur, " ") end
    path = folder .. P.SEP .. name .. " - transcription.txt"
    save_text(path, table.concat(paras, "\n\n") .. "\n")
  elseif kind == "srt" then
    local cues, cur = {}, {}
    local function flush()
      if #cur == 0 then return end
      local text = {}
      for _, w in ipairs(cur) do text[#text + 1] = w.w end
      local t = table.concat(text, " ")
      if #t > 42 then                                        -- deux lignes équilibrées
        local mid, best = #t // 2, nil
        for pos in t:gmatch("() ") do if not best or math.abs(pos - mid) < math.abs(best - mid) then best = pos end end
        if best then t = t:sub(1, best - 1) .. "\n" .. t:sub(best + 1) end
      end
      cues[#cues + 1] = { a = cur[1].a, b = cur[#cur].b, t = t }
      cur = {}
    end
    for i, w in ipairs(words) do
      local chars = 0
      for _, c in ipairs(cur) do chars = chars + #c.w + 1 end
      if #cur > 0 and (w.a - cur[#cur].b > 0.7 or w.who ~= cur[1].who or chars + #w.w > 80 or w.a - cur[1].a > 6) then flush() end
      cur[#cur + 1] = w
      if w.w:match("[%.%?!…]$") and chars > 25 then flush() end
    end
    flush()
    local out = {}
    for k, c in ipairs(cues) do
      local b = math.max(c.b, c.a + 1.0)
      if cues[k + 1] then b = math.min(b, cues[k + 1].a - 0.04) end
      out[#out + 1] = string.format("%d\n%s --> %s\n%s\n", k, tc_srt(c.a), tc_srt(b), c.t)
    end
    path = folder .. P.SEP .. name .. ".srt"
    save_text(path, table.concat(out, "\n"))
  end
  msg = "Exporté à côté du projet : " .. path
end

local function export_chapters()
  local _, fn, ddir, name = P.project()
  if not fn then msg = "Enregistrez d'abord le projet."; return end
  local list = {}
  for i = 0, reaper.CountProjectMarkers(0) - 1 do
    local _, isrgn, pos, _, nm = reaper.EnumProjectMarkers(i)
    if not isrgn and nm ~= "" and nm:sub(1, 4) ~= "PS: " then list[#list + 1] = { pos, nm } end
  end
  if #list == 0 then msg = "Aucun chapitre : placez des marqueurs (touche M) au début de chaque partie, puis nommez-les (double-clic sur le marqueur)."; return end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local lines = {}
  if list[1][1] > 1 then lines[#lines + 1] = "00:00 Introduction" end          -- YouTube exige un premier chapitre à 00:00
  for _, c in ipairs(list) do lines[#lines + 1] = tc_chap(c[1]) .. " " .. c[2] end
  local folder = fn:match("^(.*)[/\\]")
  local path = folder .. P.SEP .. name .. " - chapitres.txt"
  P.write_file(path, table.concat(lines, "\n") .. "\n")
  msg = "Chapitres exportés (format YouTube / Spotify, à coller dans la description) : " .. path
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
  if expert() then
    y, p = action_row(x, y, w, "Réglages de transcription", "Emplacement de Whisper, modèle, langue, vocabulaire.", "Réglages")
    if p then run(own("settings")) end
  end
  -- exports
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Exporter", x, y + 14, COL.text, 5)
  y = wrap("Le texte suit le montage : les passages barrés n'y sont plus. Fichiers créés à côté du projet. Chapitres : marqueurs nommés (touche M).", x, y + 38, w, COL.muted, 2) + 8
  local cx = x
  local w1, c1 = chip("Transcription (.txt)", cx, y, nil, false); cx = cx + w1 + 6
  local w2, c2 = chip("Sous-titres (.srt)", cx, y, nil, false); cx = cx + w2 + 6
  local _, c3 = chip("Chapitres (YouTube / Spotify)", cx, y, nil, false)
  if c1 then export_transcript("txt") elseif c2 then export_transcript("srt") elseif c3 then export_chapters() end
  return y + 50
end

---------------------------------------------------------------- Voix : Vocal level & de-esser, dans la page
local V                                                    -- moteur, chargé à la première visite
local function vocal()
  if not V then
    local ok, mod = pcall(dofile, dir .. "Toolbox_vocal.lua")
    if ok then V = mod end
  end
  return V
end
local VROWS = {
  { key = "rider_on", lv = "lv_rider", set = "rider", name = "Niveau régulier", desc = "Remonte les passages faibles, baisse les trop forts" },
  { key = "de_on", lv = "lv_de", set = "de", name = "Sifflantes", desc = "Adoucit les « s », « ch » et « z » qui sifflent" },
  { key = "plo_on", lv = "lv_plo", set = "plo", name = "Plosives", desc = "« p » et « b » qui soufflent dans le micro" },
  { key = "prox_on", lv = "lv_prox", set = "prox", name = "Voix trop proche", desc = "Graves qui gonflent près du micro" },
  { key = "eq_on", lv = "lv_eq", set = "eq", name = "Équilibre de la voix", desc = "Voix trop sourde, nasale ou brillante" },
}
local function fmt_db(v) return (v > 0 and "+" or (v < 0 and "−" or "")) .. string.format("%g dB", math.abs(v)) end

local function page_voice(x, y, w)
  local Vm = vocal()
  if not Vm then
    y = header(x, y, w, "Voix", "Outil introuvable : mettez la boîte à outils à jour (Extensions › ReaPack › Synchronize packages).")
    return
  end
  local S, UI, ST = Vm.S, Vm.UI, Vm.ST
  text("Voix", x, y, COL.text, 3)
  local n, an = #ST.takes, Vm.analysed_count()
  text(n == 0 and "Sélectionnez les items de voix (une fois le montage terminé)"
    or string.format("%d item%s sélectionné%s · %s", n, n > 1 and "s" or "", n > 1 and "s" or "", an == n and ("analysé" .. (n > 1 and "s" or "")) or "pas encore analysé"),
    x, y + 30, COL.muted, 2)
  local chg = false
  if button("Parole", x + w - 244, y, 96, 28, false, S.mode == "parole") then S.mode = "parole"; for k, v in pairs(Vm.PRESETS.parole) do S[k] = v end; chg = true end
  if button("Chant", x + w - 142, y, 98, 28, false, S.mode == "chant") then S.mode = "chant"; for k, v in pairs(Vm.PRESETS.chant) do S[k] = v end; chg = true end
  y = y + 58
  local why = UI.why
  for _, r in ipairs(VROWS) do
    col(COL.line); gfx.line(x, y, x + w, y)
    local on = S[r.key] == 1
    local cx, cy = x, y + 12
    col(on and COL.accent or COL.panel); gfx.rect(cx, cy, 18, 18, 1)
    if not on then col(COL.line); gfx.rect(cx, cy, 18, 18, 0) end
    if on then gfx.set(0.1, 0.06, 0.02); gfx.line(cx + 4, cy + 9, cx + 8, cy + 13); gfx.line(cx + 8, cy + 13, cx + 14, cy + 5) end
    if clicked and hit(cx - 4, cy - 4, 300, 26) then S[r.key] = on and 0 or 1; chg = true; on = not on end
    text(r.name, x + 28, y + 9, on and COL.text or COL.muted, 4)
    if why and on and why[r.key] then text(why[r.key], x + 28, y + 31, COL.ok, 2)   -- « pourquoi » : ce qui a été fait
    else text(r.desc, x + 28, y + 31, COL.muted, 2) end
    local bx = x + w - 3 * 66
    for i, lab in ipairs({ "Léger", "Moyen", "Fort" }) do
      if button(lab, bx + (i - 1) * 66, y + 7, 62, 26, false, on and S[r.lv] == i, not on) and on then
        S[r.lv] = i; for k, v in pairs(Vm.LEVELS[r.set][i]) do S[k] = v end; chg = true
      end
    end
    y = y + 58
  end
  col(COL.line); gfx.line(x, y, x + w, y)
  y = y + 12
  -- retouche locale (zone sélectionnée)
  local st, nz, zs, zt = Vm.zone_state()
  text("Retouche locale", x, y, COL.text, 4)
  if st then
    text(string.format("zone %.2f → %.2f s%s", zs, zt, nz > 0 and string.format(" · %d retouche%s", nz, nz > 1 and "s" or "") or ""), x + 140, y + 1, COL.accent, 2)
    if nz > 0 and button("Effacer", x + w - 90, y - 4, 90, 24) then Vm.retouch(nil) end
  else
    text("sélection temporelle sur le son à retoucher (ex. le « B » de « Bonjour »)", x + 140, y + 1, COL.muted, 2)
  end
  y = y + 26
  local cw3 = (w - 2 * 12) / 3
  for j, k in ipairs(Vm.RET_ORDER) do
    local R = Vm.RET[k]
    local gx = x + (j - 1) * (cw3 + 12)
    text(R.name, gx, y + 4, st and COL.text or COL.muted, 2)
    local bw = (cw3 - 70) / 4
    for i, v in ipairs(R.steps) do
      local shown = (k == "lvl") and v or -v
      if button(fmt_db(shown):gsub(" dB", ""), gx + 70 + (i - 1) * bw, y, bw - 3, 24, false, st and st[k] == v, not st) and st then Vm.retouch(k, v) end
    end
  end
  y = y + 38
  -- actions
  if UI.progress then col(COL.line); gfx.rect(x, y, w, 6, 1); col(COL.accent); gfx.rect(x, y, math.floor(w * UI.progress), 6, 1); y = y + 12 end
  if UI.stats then text(UI.stats, x, y, COL.ok, 2); y = y + 18 end
  if UI.msg ~= "" then text(UI.msg, x, y, COL.muted, 2); y = y + 18 end
  y = y + 6
  if ST.job and ST.cancel_job then
    if button("Annuler l'analyse", x, y, 220, 36) then ST.cancel_job() end
  else
    local done, byp = Vm.fx_state()
    if done then
      if button(byp and "Bypass (son d'origine)" or "Bypass", x, y, 220, 36, false, byp) then Vm.toggle_bypass() end
    elseif button("Analyser et appliquer", x, y, 220, 36, true, false, n == 0) then Vm.start_analysis() end
  end
  if button("Guide", x + 230, y, 90, 36) then open_url(dir .. "Vocal level - Guide.html") end
  if expert() then
    if button("Retirer", x + 330, y, 90, 36) then
      local k = Vm.remove_all(ST.takes); UI.stats, UI.why = nil, nil
      Vm.set_msg(k > 0 and string.format("Traitement retiré de %d item%s.", k, k > 1 and "s" or "") or "Rien à retirer sur la sélection.")
    end
    if vocal_path and button("Réglages avancés…", x + w - 180, y, 180, 36) then run(vocal_path) end
  end
  if chg and not ST.job then
    if an > 0 then Vm.apply_all() else Vm.save() end
  end
  return y + 50
end

-- ripple sur les bords relancé à chaque démarrage de REAPER (bloc ajouté au fichier __startup.lua de REAPER)
local MARK1, MARK2 = "-- >>> Podcast & ADR Toolbox : ripple sur les bords au démarrage", "-- <<< Podcast & ADR Toolbox"
local function startup_path() return reaper.GetResourcePath() .. P.SEP .. "Scripts" .. P.SEP .. "__startup.lua" end
local auto_cache
function autostart_on()
  if auto_cache == nil then auto_cache = (P.read_file(startup_path()) or ""):find(MARK1, 1, true) ~= nil end
  return auto_cache
end
function set_autostart(on)
  local path = startup_path()
  local s = P.read_file(path) or ""
  local a = s:find(MARK1, 1, true)
  if a then
    local _, b = s:find(MARK2, a, true)
    s = (s:sub(1, a - 1):gsub("\n+$", "")) .. (b and s:sub(b + 1) or "")
  end
  if on then
    local cmd = cmd_of(own("ripple"))
    local named = cmd and reaper.ReverseNamedCommandLookup(cmd)
    if named and named ~= "" then
      s = (s:gsub("%s+$", "")) .. (s ~= "" and "\n\n" or "") .. MARK1 .. "\nlocal id = reaper.NamedCommandLookup(\"_" .. named .. "\")\nif id ~= 0 then reaper.Main_OnCommand(id, 0) end\n" .. MARK2 .. "\n"
    end
  end
  P.write_file(path, s)
  auto_cache = nil
end

local function page_cut(x, y, w)
  y = header(x, y, w, "Outils d'édition", "Cette page ne monte rien à votre place : elle règle le comportement des outils d'édition de REAPER. Le ripple editing fait suivre la suite du montage quand on supprime ou déplace un item. La boîte à outils ajoute le ripple sur les bords, et l'aimantation garde les items collés les uns aux autres.")
  -- aimantation
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Aimantation des items (snap)", x, y + 14, COL.text, 5)
  if SNAP.toggle then
    local on = snap_on()
    if button(on and "Activée" or "Désactivée", x + w - 150, y + 12, 150, 30, false, on) then set_snap(not on) end
    y = wrap("Quand on déplace un item ou qu'on tire un de ses bords, il se colle au bord des items voisins. La grille n'aimante pas" ..
      (SNAP.grid and "." or " : si les items sautent encore de division en division, décochez « Grid » dans Options › Snap/Grid settings."), x, y + 48, w - 180, COL.muted, 2) + 16
  else
    y = wrap("Activez l'aimant de la barre d'outils de REAPER (clic droit dessus pour cocher l'aimantation aux items).", x, y + 48, w, COL.muted, 2) + 16
  end
  if expert() then
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
  end
  -- ripple sur les bords
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Ripple sur les bords des items", x, y + 14, COL.text, 5)
  local on = is_on(own("ripple"))
  if button(on and "Activé" or "Désactivé", x + w - 150, y + 12, 150, 30, false, on) then
    if on then reaper.SetExtState(SEC, "ripple_stop", "1", false); set_autostart(false)
    else run(own("ripple")); set_autostart(true) end
  end
  local auto = autostart_on()
  local _, ac = chip((auto and "✓ " or "") .. "Activer au démarrage de REAPER", x, y + 46, nil, auto)
  if ac then set_autostart(not auto) end
  y = y + 38
  y = wrap("Pendant que vous tirez un bord, les voisins se décalent en direct, de la même valeur : bord droit, tout ce qui suit ; bord gauche, tout ce qui précède. Aucun fondu n'est ajouté. Même portée que le ripple de REAPER (la piste, ou toutes les pistes).", x, y + 48, w - 24, COL.muted, 2) + 10
end

---------------------------------------------------------------- Export : contrôle du niveau dans la page, liste « prêt ? », export
local LD
local function loud()
  if not LD then
    local ok, mod = pcall(dofile, dir .. "Toolbox_loudness.lua")
    if ok then LD = mod end
  end
  return LD
end

local function tile(x, y, w, h, label, value, sub, ok)
  col(COL.panel); gfx.rect(x, y, w, h, 1)
  col(ok == nil and COL.line or (ok and COL.ok or COL.bad)); gfx.rect(x, y, 4, h, 1)
  text(label, x + 14, y + 9, COL.muted, 2)
  text(value, x + 14, y + 28, ok == nil and COL.text or (ok and COL.ok or COL.bad), 3)
  text(sub, x + 14, y + 56, COL.muted, 2)
end

-- vérifications avant l'export (rapides, recalculées quand le projet change)
local ready_cache = { st = -1 }
local function ready_checks(Lm)
  local st = reaper.GetProjectStateChangeCount(0)
  if st ~= ready_cache.st then
    local solo, voice = false, false
    for i = 0, reaper.CountTracks(0) - 1 do
      if reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_SOLO") > 0 then solo = true end
    end
    for i = 0, math.min(reaper.CountMediaItems(0), 400) - 1 do
      local tk = reaper.GetActiveTake(reaper.GetMediaItem(0, i))
      if tk and reaper.TakeFX_GetCount(tk) > 0 then
        for f = 0, reaper.TakeFX_GetCount(tk) - 1 do
          local _, nm = reaper.TakeFX_GetFXName(tk, f, "")
          if nm:find("Vocal level", 1, true) then voice = true end
        end
      end
      if voice then break end
    end
    local _, fn = reaper.EnumProjects(-1)
    ready_cache = { st = st, solo = solo, voice = voice, saved = fn ~= nil and fn ~= "" }
  end
  local R = ready_cache
  local m = Lm.UI.m
  local okLevel = m and (function() local a, b = Lm.verdict(m, Lm.NORMS[Lm.S.norm]); return a and b end)()
  return {
    { R.saved, "Projet enregistré", "Fichier › Enregistrer le projet" },
    { not R.solo, "Aucune piste en solo", "une piste en solo exporterait un mix incomplet" },
    { R.voice, "Voix traitée (page Voix)", "facultatif, mais conseillé" },
    { okLevel, "Niveau conforme à la norme", m and "voir les pistes ci-dessus" or "cliquez sur « Mesurer »" },
  }
end

-- MP3 CBR 320 kbps, qualité maximale (structure du format « l3pm » de REAPER, d'après l'API Ultraschall)
local MP3_320 = "bDNwbUABAAAAAAAAAAAAAP////8EAAAAQAEAAAAAAAA="
-- sélectionne les items audibles et place les points d'entrée/sortie (sélection temporelle) autour d'eux
local function prepare_mp3()
  local a, b, n = math.huge, -math.huge, 0
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(40289, 0)                              -- Item: Unselect all items
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local muted = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1
    local par = reaper.GetParentTrack(tr)
    while par and not muted do muted = reaper.GetMediaTrackInfo_Value(par, "B_MUTE") == 1; par = reaper.GetParentTrack(par) end
    if not muted then
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if reaper.GetMediaItemInfo_Value(it, "B_MUTE") ~= 1 then
          local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if p < a then a = p end
          if e > b then b = e end
          reaper.SetMediaItemSelected(it, true); n = n + 1
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
  if n == 0 then return 0 end
  reaper.GetSet_LoopTimeRange(true, false, a, b, false)
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 512, true)       -- master, métadonnées intégrées au fichier
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 2, true)       -- sélection temporelle
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 44100, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_TAILFLAG", 0, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", MP3_320, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$project", true)
  -- fenêtre d'export pré-réglée, puis fenêtre des métadonnées par-dessus. Si la fenêtre d'export bloque REAPER
  -- jusqu'à sa fermeture (Main_OnCommand ne rend la main qu'après), on n'ouvre pas les métadonnées après coup.
  local t = reaper.time_precise()
  reaper.Main_OnCommand(40015, 0)                              -- File: Render project to disk…
  local blocked = reaper.time_precise() - t > 1
  if META and not blocked then reaper.Main_OnCommand(META, 0) end
  return n, (META and not blocked)
end

local function page_export(x, y, w)
  local Lm = loud()
  if not Lm then y = header(x, y, w, "Export", "Outil introuvable : mettez la boîte à outils à jour (ReaPack › Synchronize packages)."); return y end
  local S, UI, NORMS = Lm.S, Lm.UI, Lm.NORMS
  text("Export", x, y, COL.text, 3)
  text("Mesure le mix du master tel qu'il sera exporté, avant d'exporter, selon la norme choisie.", x, y + 30, COL.muted, 2)
  y = y + 60
  local vis = {}
  for i in ipairs(NORMS) do vis[#vis + 1] = i end
  local per = math.min(#vis, 4)
  local bw = (w - (per - 1) * 10) / per
  for k, i in ipairs(vis) do
    local col_, row = (k - 1) % per, (k - 1) // per
    if button(NORMS[i].name, x + col_ * (bw + 10), y + row * 38, bw, 30, false, S.norm == i) and not UI.busy then S.norm = i; Lm.save() end
  end
  y = y + ((#vis - 1) // per) * 38
  local N = NORMS[S.norm]
  y = y + 36
  if N.editable then                                         -- cible du podcast réglable
    text("Cible", x, y + 7, COL.text, 4)
    local cx = x + 60
    if button("−", cx, y, 30, 28) and not UI.busy then Lm.set_podcast_target(N.target - 1) end
    gfx.setfont(4); col(COL.text); local lab = Lm.num(N.target, 0) .. " LUFS"
    gfx.x, gfx.y = cx + 38, y + 7; gfx.drawstr(lab)
    cx = cx + 46 + gfx.measurestr(lab)
    if button("+", cx, y, 30, 28) and not UI.busy then Lm.set_podcast_target(N.target + 1) end
    cx = cx + 44
    for _, v in ipairs({ { -16, "−16 podcast" }, { -14, "−14 Spotify / YouTube" }, { -23, "−23 radio" } }) do
      local cw2, cc = chip(v[2], cx, y, nil, N.target == v[1]); if cc and not UI.busy then Lm.set_podcast_target(v[1]) end
      cx = cx + cw2 + 6
    end
    y = y + 38
  end
  local dd = (N.tol % 1 ~= 0) and 1 or 0
  text(string.format("Norme : %s LUFS intégrés (± %s LU) · true peak max %s dBTP", Lm.num(N.target, 0), Lm.num(N.tol, dd), Lm.num(N.tp, 0)), x, y, COL.muted, 2)
  y = y + 26
  if expert() then
    local w2, c1 = chip("Tout le projet", x, y, nil, S.scope == "all"); if c1 and not UI.busy then S.scope = "all"; Lm.save() end
    local _, c2 = chip("Sélection temporelle", x + w2 + 6, y, nil, S.scope == "sel"); if c2 and not UI.busy then S.scope = "sel"; Lm.save() end
    y = y + 38
  else S.scope = "all" end
  if button(UI.busy and "Mesure…" or (UI.m and "Remesurer" or "Mesurer"), x, y, 200, 36, true) and not UI.busy then Lm.do_measure() end
  local g, en = Lm.lim_gain()
  if g then
    text(string.format("Limiteur sur le master : gain %s dB%s", Lm.sgn(g), en and "" or " (désactivé)"), x + 214, y + 2, COL.muted, 2)
    if button("Retirer le limiteur", x + 214, y + 20, 160, 22) and not UI.busy then Lm.remove_lim() end
  end
  y = y + 50
  if UI.msg ~= "" then y = wrap(UI.msg, x, y, w, COL.accent, 2) + 6 end
  local m = UI.m
  if m then
    local okL, okT = Lm.verdict(m, N)
    local tw = (w - 24) / 3
    tile(x, y, tw, 76, "Loudness intégrée", Lm.num(m.lufs) .. " LUFS", string.format("visé : %s à %s", Lm.num(N.target - N.tol, dd), Lm.num(N.target + N.tol, dd)), okL)
    tile(x + tw + 12, y, tw, 76, m.tp_src == "sample" and "Crête (échantillon)" or "True peak", Lm.sgn(m.tp) .. (m.tp_src == "sample" and " dBFS" or " dBTP"),
      m.tp_src == "sample" and ("max : " .. Lm.num(N.tp - 1, 0) .. " dBFS") or ("max : " .. Lm.num(N.tp, 0) .. " dBTP"), okT)
    tile(x + 2 * (tw + 12), y, tw, 76, "Écart de volume (LRA)", m.lra and (Lm.num(m.lra) .. " LU") or "—", "bas = voix régulière", m.lra and (m.lra <= Lm.LRA_HIGH) or nil)
    y = y + 90
    for _, s in ipairs(Lm.suggestions(m, N)) do
      col(COL.accent); gfx.rect(x + 2, y + 6, 5, 5, 1)
      y = wrap(s, x + 16, y, w - 16, COL.text, 2) + 4
    end
    if not (okL and okT) then
      y = y + 4
      if button("Corriger automatiquement", x, y, 240, 34, true) and not UI.busy then Lm.do_correct() end
      y = y + 42
    end
  end
  -- prêt à exporter ?
  y = y + 6
  col(COL.line); gfx.line(x, y, x + w, y)
  text("Prêt à exporter ?", x, y + 12, COL.text, 5)
  y = y + 40
  local allok = true
  for _, c in ipairs(ready_checks(Lm)) do
    if not c[1] and c[2] == "Voix traitée (page Voix)" then col(COL.accent); gfx.circle(x + 6, y + 8, 5, 1, 1) else status_dot(x + 6, y + 8, c[1]) end
    text(c[2], x + 20, y, c[1] and COL.text or COL.muted, 2)
    if not c[1] then text(c[3], x + 260, y, COL.muted, 2); if c[2] ~= "Voix traitée (page Voix)" then allok = false end end
    y = y + 22
  end
  y = y + 8
  if N.use == "podcast" then
    -- podcast : MP3 320 kbps, du début du premier item à la fin du dernier, tags ID3 remplis avant l'export
    if button("Préparer et lancer l'export (MP3 320 kbps)", x, y, 380, 36, allok, false) then
      local n, meta = prepare_mp3()
      if n == 0 then msg = "Aucun item audible à exporter."
      else
        msg = "Export préparé : MP3 320 kbps, 44,1 kHz, du début du premier item à la fin du dernier (" .. n .. " items sélectionnés). " ..
          (meta and "Remplissez les tags (titre, artiste, album, image…) dans la fenêtre des métadonnées, puis cliquez sur « Render 1 file » dans la fenêtre d'export."
            or "Pour les tags (titre, artiste, image…), cliquez sur « Metadata… » dans la fenêtre d'export, puis sur « Render 1 file ».")
      end
    end
    y = y + 44
    wrap("Pas de normalisation à l'export : le niveau est déjà réglé par la mesure et la correction ci-dessus.", x, y, w, COL.muted, 2)
  elseif button("Exporter : " .. N.name, x, y, 340, 36, allok, false) then
    -- réglages de rendu prêts : tout le projet, 44,1 kHz, nom du fichier ; le format (MP3, WAV…) reste au choix
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
    reaper.GetSetProjectInfo(0, "RENDER_SRATE", N.srate or 48000, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$project - " .. (N.short or "export"), true)
    reaper.Main_OnCommand(40015, 0)
    msg = N.use == "adr"
      and "Fenêtre d'export ouverte (48 kHz) : choisissez WAV 24 bits et ne cochez pas de normalisation — le niveau est déjà réglé. Pour livrer les voix seules à un mixeur, utilisez plutôt « Exporter une piste par personnage » (page Enregistrement), sans traitement de niveau."
      or "Fenêtre d'export ouverte : choisissez le format (MP3 192 kbps ou WAV) et ne cochez pas de normalisation — le niveau est déjà réglé."
  end
  return y + 50
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
  do
    local em, dk = A.get("tr_email", ""), A.get("deepl_key", "")
    local lab = dk ~= "" and "Traduction : DeepL (clé personnelle)" or em ~= "" and ("Traduction : MyMemory · " .. em) or "Traduction : MyMemory (limite partagée)"
    local tw2, tc = chip("⚙ " .. lab, x, y + 2, nil, false)
    if tc then
      local ok, v = reaper.GetUserInputs("Réglages de traduction", 2, "Votre e-mail (limite × 10),Clé DeepL Free (facultatif),extrawidth=260", em .. "," .. dk)
      if ok then
        local e2, k2 = v:match("^([^,]*),(.*)$")
        A.set("tr_email", (e2 or ""):match("^%s*(.-)%s*$")); A.set("deepl_key", (k2 or ""):match("^%s*(.-)%s*$"))
      end
    end
    y = y + 40
  end
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
  -- retirer les voix de la VO
  y = cy + 46
  local pu
  y, pu = action_row(x, y, w, "Retirer les voix de la VO", "Pour garder la musique et les bruitages sous le doublage : Ultimate Vocal Remover (gratuit, Mac et Windows, hors ligne) sépare les voix du reste. Importez ensuite la piste sans voix dans REAPER.", "Télécharger UVR")
  if pu then open_url("https://github.com/Anjok07/ultimatevocalremovergui/releases") end
end

local tablet_url
local function adr_server_on() return is_on(own("adr_server")) end
local function ensure_adr_server() if not adr_server_on() then run(own("adr_server")) end end

function rec_go(D, i, how)
  local l = D.lines[i]; if not l then return end
  ensure_adr_server()
  local preroll = tonumber(A.get("preroll", "3")) or 0             -- « Off » = 0
  local continuous = A.get("rec_mode", "line") == "free"
  if reaper.GetPlayState() & 5 ~= 0 then reaper.OnStopButton() end
  reaper.Undo_BeginBlock()
  A.cue(l, preroll)
  A.set("curpos", string.format("%.3f", l.pos))
  reaper.Undo_EndBlock("Toolbox : réplique " .. i, -1)
  if continuous then reaper.DeleteExtState(A.SEC, "stop_at", false) end   -- en continu : pas d'arrêt automatique
  if how == "listen" then reaper.Main_OnCommand(1007, 0)
  elseif how == "rec" then
    local mode = A.cmd(continuous and "normal" or "punch"); if mode then reaper.Main_OnCommand(mode, 0) end
    if continuous then reaper.DeleteExtState(A.SEC, "punch_on", false) else reaper.SetExtState(A.SEC, "punch_on", "1", false) end
    reaper.Main_OnCommand(1013, 0)
  end
end
local GREEN, RED = { 0.19, 0.62, 0.34 }, { 0.86, 0.22, 0.2 }

-- prises d'une réplique : items (et prises internes) de la piste « Prises - Nom » qui recouvrent la réplique
local function line_takes(l)
  local tr = A.find_track(A.REC_PREFIX .. l.who)
  local out = {}
  if not tr then return out end
  local a, b = l.pos - 0.5, l.pos + l.len + 1
  for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, j)
    local p0 = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local p1 = p0 + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p1 > a and p0 < b then
      local act = reaper.GetActiveTake(it)
      for k = 0, reaper.CountTakes(it) - 1 do
        local tk = reaper.GetTake(it, k)
        out[#out + 1] = { item = it, take = tk, current = reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 and tk == act,
          kept = reaper.GetMediaItemInfo_Value(it, "I_CUSTOMCOLOR") == (reaper.ColorToNative(48, 209, 88) | 0x1000000) and tk == act }
      end
    end
  end
  return out
end
local function choose_take(list, n, keep)
  local e = list[n]; if not e then return end
  reaper.Undo_BeginBlock()
  for _, o in ipairs(list) do
    if o.item ~= e.item then
      reaper.SetMediaItemInfo_Value(o.item, "B_MUTE", 1)
      if keep then reaper.SetMediaItemInfo_Value(o.item, "I_CUSTOMCOLOR", 0) end
    end
  end
  reaper.SetMediaItemInfo_Value(e.item, "B_MUTE", 0)
  reaper.SetActiveTake(e.take)
  if keep then reaper.SetMediaItemInfo_Value(e.item, "I_CUSTOMCOLOR", reaper.ColorToNative(48, 209, 88) | 0x1000000) end
  reaper.Undo_EndBlock(keep and "Toolbox : prise gardée" or "Toolbox : choix de la prise", -1)
  reaper.UpdateArrange()
end

local function page_rec(x, y, w)
  y = header(x, y, w, "Enregistrement", "La bande rythmo s'affiche dans un navigateur : sur l'écran de la cabine ou sur une tablette du même réseau Wi-Fi, avec la vidéo du film au-dessus, calée sur REAPER.")
  local D = adr_data()
  local on = adr_server_on()
  do                                                         -- la séance est-elle prête ?
    local vstate0 = (reaper.GetExtState(A.SEC, "video"):match("([^|]*)$")) or ""
    local checks = {
      { #D.lines > 0, #D.lines > 0 and string.format("%d réplique%s", #D.lines, #D.lines > 1 and "s" or "") or "Pas de répliques" },
      { A.get("focus", "") ~= "", A.get("focus", "") ~= "" and ("Personnage : " .. A.get("focus", "")) or "Choisir le personnage" },
      { on, on and "Bande ouverte" or "Bande à ouvrir" },
      { vstate0 == "ok", vstate0 == "ok" and "Vidéo envoyée" or "Vidéo : —" },
    }
    local cx = x
    for _, c in ipairs(checks) do
      status_dot(cx + 6, y + 8, c[1]); text(c[2], cx + 18, y + 1, c[1] and COL.text or COL.muted, 2)
      gfx.setfont(2); cx = cx + 18 + gfx.measurestr(c[2]) + 22
    end
    y = y + 30
  end
  local port = P.web_port()
  local p
  y, p = action_row(x, y, w, "Bande rythmo", port and ("Sur la tablette (même Wi-Fi) : " .. (tablet_url or "adresse de cet ordinateur, port " .. port) .. "") or "L'interface web de REAPER n'est pas activée : Accueil › Installer / réparer.",
    "Ouvrir sur cet ordinateur", true, not port,
    function(ax, ay) status_dot(ax + 6, ay + 8, on); text(on and "Serveur de la bande actif" or "Serveur arrêté (il démarre avec la bande)", ax + 18, ay + 1, on and COL.ok or COL.muted, 2) end)
  if p then ensure_adr_server(); open_url(P.web_url("doublage.html")) end
  -- vidéo sur la tablette
  local vinfo = reaper.GetExtState(A.SEC, "video")
  local vstate = vinfo:match("([^|]*)$") or ""
  local vtxt = not on and "Vidéo : envoyée à la tablette quand la bande est ouverte."
    or vstate == "ok" and "Vidéo du projet affichée au-dessus de la bande, calée sur REAPER."
    or vstate == "none" and "Aucune vidéo dans le projet (Insert › Media file… pour l'ajouter)."
    or vstate:find("^copie") and ("Vidéo : préparation pour la tablette, " .. vstate:gsub("copie ", "") .. "…")
    or vstate == "off" and "Vidéo masquée sur la bande." or "Vidéo : …"
  local vw, vc = chip((A.get("show_video", "1") == "1" and "✓ " or "") .. "Vidéo sur la bande", x, y, nil, A.get("show_video", "1") == "1")
  if vc then A.set("show_video", A.get("show_video", "1") == "1" and "0" or "1") end
  text(vtxt, x + vw + 12, y + 7, vstate == "ok" and COL.ok or COL.muted, 2)
  y = y + 40
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
  y = y + 92
  -- prises de la réplique
  if i then
    local tl = line_takes(lines[i])
    local cur = 0
    for k, e in ipairs(tl) do if e.current then cur = k end end
    if #tl == 0 then text("Pas encore de prise pour cette réplique.", x, y + 5, COL.muted, 2)
    else
      local kept = false
      for _, e in ipairs(tl) do if e.kept then kept = true end end
      text(string.format("Prise %d / %d%s", math.max(cur, 1), #tl, kept and "  ·  ★ gardée" or ""), x, y + 5, kept and COL.ok or COL.text, 4)
      local bx = x + 170
      if button("◀", bx, y, 34, 26, false, false, cur <= 1) then choose_take(tl, cur - 1) end
      if button("▶", bx + 38, y, 34, 26, false, false, cur >= #tl) then choose_take(tl, cur + 1) end
      if button("★ Garder cette prise", bx + 80, y, 180, 26, false, false, cur == 0) then choose_take(tl, cur, true) end
    end
    y = y + 38
  end
  -- transport
  local bw = (w - 3 * 8) / 4
  local dis = not i
  local ps = reaper.GetPlayState()
  local running, recording = ps & 1 == 1, ps & 4 == 4
  if button("◀  Précédente", x, y, bw, 40, false, false, dis or i <= 1 or recording) then rec_go(D, i - 1) end
  if button(running and "■  Arrêter" or "▶  Écouter", x + (bw + 8), y, bw, 40, false, false, dis and not running, GREEN) then
    if running then reaper.OnStopButton() else rec_go(D, i, "listen") end
  end
  if button(recording and "●  Enregistrement…" or "●  Enregistrer", x + 2 * (bw + 8), y, bw, 40, false, false, dis or running, RED) then rec_go(D, i, "rec") end
  if button("Suivante  ▶", x + 3 * (bw + 8), y, bw, 40, false, false, dis or i >= #lines or recording) then rec_go(D, i + 1) end
  y = y + 52
  -- mode d'enregistrement (expert)
  if not expert() and A.get("rec_mode", "line") == "free" then A.set("rec_mode", "line") end
  if expert() then
  text("Enregistrer", x, y + 7, COL.muted, 2)
  local free = A.get("rec_mode", "line") == "free"
  local mx = x + 90
  local w1, c1 = chip("Une réplique (arrêt automatique)", mx, y, nil, not free); if c1 then A.set("rec_mode", "line") end
  local _, c2 = chip("En continu (jusqu'à « Arrêter »)", mx + w1 + 6, y, nil, free); if c2 then A.set("rec_mode", "free") end
  y = y + 40
  end
  -- options
  local function toggle(label, key, def, ox)
    local v = A.get(key, def) == "1"
    local lab = (v and "✓ " or "") .. label
    gfx.setfont(4); local need = gfx.measurestr(lab) + 28
    if ox > x and ox + need > x + w then y = y + 38; cx = x; ox = x end   -- plus de place : ligne suivante
    local w2, c2 = chip(lab, ox, y, nil, v); if c2 then A.set(key, v and "0" or "1") end
    cx = ox + w2 + 6
  end
  cx = x
  toggle("Bips", "bips", "1", cx)
  if expert() then
  if A.get("rec_mode", "line") ~= "free" then
    toggle("Répéter avant d'enregistrer", "loop", "0", cx)
    -- pendant la répétition (lecture, pas d'enregistrement) : bips au choix ; en enregistrement, ils suivent « Bips »
    if A.get("loop", "0") == "1" then toggle("Bips en répétition (B)", "bips_play", "0", cx) end
  end
  toggle("Suivante après la prise", "auto_next", "1", cx)
  y = y + 38; cx = x
  text("Pré-roll", cx, y + 7, COL.muted, 2); cx = cx + 70
  local pr = A.get("preroll", "3")
  for _, v in ipairs({ "off", "2", "3", "4", "5" }) do
    local w2, c2 = chip(v == "off" and "Off" or (v .. " s"), cx, y, nil, pr == v); if c2 then A.set("preroll", v) end
    cx = cx + w2 + 4
  end
  if pr == "off" and A.get("bips", "1") == "1" then text("(sans pré-roll, pas de bips)", cx + 8, y + 7, COL.muted, 2) end
  end
  y = y + 42
  y = wrap("Raccourcis : ← / → réplique précédente / suivante · R enregistrer · Espace écouter/arrêter · B bips en répétition. Chaque passage crée une nouvelle prise sur la piste « Prises - Personnage » ; ◀ ▶ pour les comparer, ★ pour garder la meilleure." .. (expert() and " En continu, l'enregistrement part de la réplique affichée et enchaîne jusqu'à « Arrêter »." or ""), x, y, w, COL.muted, 2)
  if expert() then
    y = y + 10
    if button("Exporter une piste par personnage…", x, y, 300, 32) then
      local n = 0
      for t = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, t)
        local _, nm = reaper.GetTrackName(tr)
        local want = nm:sub(1, #A.REC_PREFIX) == A.REC_PREFIX
        reaper.SetTrackSelected(tr, want); if want then n = n + 1 end
      end
      if n == 0 then msg = "Aucune piste « Prises - … » dans ce projet."
      else
        reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 3, true)          -- source « Stems (selected tracks) » : un fichier par piste
        reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
        reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$project - $track", true)
        reaper.Main_OnCommand(40015, 0)
        msg = string.format("%d piste%s de prises sélectionnée%s. Dans la fenêtre d'export, « Source » doit indiquer « Stems (selected tracks) » : un fichier par personnage (WAV 24 bits conseillé). Ne changez pas la sélection des pistes avant de cliquer sur « Render ».", n, n > 1 and "s" or "", n > 1 and "s" or "")
      end
    end
    y = y + 40
  end
  return y + 20
end

---------------------------------------------------------------- Aide de chaque page (bouton « ? »)
local HELP = {
  home = { "Bienvenue", {
    "Cette fenêtre réunit tous les outils, dans l'ordre du travail : 1 Dérushage, 2 Édition, 3 Voix, 4 Export. Le doublage a ses deux pages : 5 Répliques et 6 Enregistrement.",
    "Pastille rouge dans « Installation » : cliquez sur « Installer / réparer » (une seule fois par ordinateur).",
    "Ctrl/Cmd+Z annule, la barre d'espace lance ou arrête la lecture, même quand cette fenêtre est active." } },
  edit = { "Dérushage", {
    "1. Enregistrez le projet. 2. Sélectionnez les items des micros (un par intervenant). 3. « Transcrire la sélection ».",
    "La page de dérushage s'ouvre dans le navigateur : barrez les mots à couper. REAPER reconstruit le montage sur des pistes « ✂ » ; les rushes ne sont jamais modifiés.",
    "Le clicker : un clic pendant l'enregistrement = « prise ratée ». Calibrez-le une fois : PodSuite repère ensuite les clics et propose les coupes.",
    "Exports (transcription, sous-titres, chapitres) : boutons en bas de la page." } },
  cut = { "Outils d'édition", {
    "Aimantation : les items se collent aux bords de leurs voisins quand on les déplace.",
    "Ripple sur les bords : quand on raccourcit ou rallonge un item par un bord, ce qui suit (bord droit) ou ce qui précède (bord gauche) se décale d'autant, en direct.",
    "Ripple editing de REAPER (par piste ou toutes les pistes) : pour les suppressions et déplacements d'items." } },
  voice = { "Voix", {
    "À faire une fois le montage terminé. Sélectionnez les items de voix puis « Analyser et appliquer ».",
    "Chaque traitement a trois intensités. Commencez en Moyen, écoutez au casque, puis ajustez : si la voix devient étouffée ou creuse, c'est trop fort.",
    "« Bypass » compare avec le son d'origine. Les courbes dessinées sur les items montrent ce qui a été fait." } },
  export = { "Export", {
    "LUFS : le volume perçu, mesuré sur tout le fichier. Podcast : −16 LUFS par défaut (± 1), réglable : −14 pour Spotify ou YouTube, −23 pour la radio. Doublage : télévision −23 LUFS (EBU R128, ± 0,5), Netflix −27 LUFS sur les dialogues (± 2, true peak −2 dBTP), web −14 LUFS.",
    "Les normes proposées dépendent du choix « Je fais du podcast / du doublage / les deux » dans l'Accueil.",
    "True peak : la crête réelle du son, entre les échantillons. Elle ne doit pas dépasser −1 dBTP, sinon le son sature après compression MP3.",
    "« Corriger automatiquement » ajoute un limiteur en fin de chaîne du master et règle le gain. Si le limiteur doit trop travailler, régularisez d'abord la voix." } },
  lines = { "Répliques", {
    "Une réplique = un item vide sur la piste « @Personnage », avec le texte dans ses notes. Déplacez ou étirez l'item pour le caler sur l'image.",
    "Depuis la VO : Whisper place chaque réplique sur le temps de parole ; choisissez la langue de traduction avant de lancer.",
    "En salle de cours, la traduction gratuite est vite épuisée : ⚙ Réglages de traduction, ajoutez votre e-mail (ou une clé DeepL gratuite).",
    "Signes de détection dans le texte : (r) respiration, (b) bouche fermée, (rire), (s) soupir." } },
  rec = { "Enregistrement", {
    "Ouvrez la bande sur l'écran de la cabine (ou la tablette). Le comédien voit l'image, la réplique à dire en entier, puis la bande qui défile.",
    "Choisissez le personnage, puis Précédente / Suivante pour vous placer. Écouter (vert) pour répéter, Enregistrer (rouge) pour la prise.",
    "Double bip avant la réplique : « bip, bip, top », on parle au troisième temps.",
    "« Répéter avant d'enregistrer » : avec « Écouter », la réplique est rejouée en boucle (pré-roll compris) jusqu'à « Arrêter », pour que le comédien cale son rythme. Sans effet pendant l'enregistrement. « Bips en répétition » (touche B) fait entendre ou coupe les bips pendant ces répétitions, même en pleine lecture ; à l'enregistrement, les bips suivent l'option « Bips ».",
    "Chaque passage crée une prise sur la piste « Prises - Personnage ». En continu : enchaîner plusieurs répliques jusqu'à « Arrêter »." } },
}
local help_open = false
local function help_overlay(x, y, w, h)
  local H = HELP[page]; if not H then return end
  col(COL.side); gfx.rect(x - 12, y - 10, w + 24, h, 1)
  col(COL.accent); gfx.rect(x - 12, y - 10, 4, h, 1)
  text("Aide · " .. H[1], x, y, COL.text, 3)
  local yy = y + 44
  for _, para in ipairs(H[2]) do yy = wrap(para, x, yy, w, COL.text, 1) + 12 end
  if button("Fermer l'aide", x, yy + 6, 160, 30) then help_open = false end
end

local DRAW = { home = page_home, edit = page_edit, voice = page_voice, cut = page_cut, export = page_export, lines = page_lines, rec = page_rec }


local function draw()
  local w, h = U.W(), U.H()
  col(COL.bg); gfx.rect(0, 0, w, h, 1)
  local sw = 190
  col(COL.side); gfx.rect(0, 0, sw, h, 1)
  text("Podcast &", 22, 18, COL.text, 3)
  text("ADR Toolbox", 22, 42, COL.text, 3)
  local y = 84
  for _, pg in ipairs(PAGES) do
    if not shown(pg) then goto continue end
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
  gfx.setfont(2); col(COL.muted)
  gfx.x, gfx.y = 18, h - 34; gfx.drawstr("Version " .. P.VERSION .. " · Nouveautés")
  if clicked and hit(16, h - 38, sw - 32, 20) then open_url("https://github.com/nicolasdebois-pixel/PodSuite/blob/main/CHANGELOG.md") end
  local cx, cw = sw + 32, math.max(300, w - sw - 64)
  if help_open then help_overlay(cx, 26, cw, h - 40)
  else
    if (gfx.mouse_wheel or 0) ~= 0 then SCROLL = math.max(0, (SCROLL or 0) - gfx.mouse_wheel / 4); gfx.mouse_wheel = 0 end
    if page ~= LAST_PAGE then SCROLL, LAST_PAGE = 0, page end
    local bottom = DRAW[page](cx, 26 - (SCROLL or 0), cw)
    if type(bottom) == "number" then
      local over = bottom + (SCROLL or 0) - (h - 10)
      if over <= 0 then SCROLL = 0 elseif SCROLL > over then SCROLL = over end
      if over > 0 then                                         -- indicateur de défilement
        col(COL.line); gfx.rect(w - 6, 0, 3, h, 1)
        col(COL.muted); gfx.rect(w - 6, (SCROLL / (over + h)) * h, 3, h * h / (over + h), 1)
      end
    else SCROLL = 0 end
  end
  if button(help_open and "×" or "?", w - 46, 18, 30, 30, false, help_open) then help_open = not help_open end
  -- message (résultat d'un outil, avertissement) : en bas, refermable
  if msg ~= "" then
    gfx.setfont(2)
    local lines = {}
    for para in (msg .. "\n"):gmatch("(.-)\n") do
      local line = ""
      for word in para:gmatch("%S+") do
        local t2 = line == "" and word or (line .. " " .. word)
        if gfx.measurestr(t2) > cw - 40 and line ~= "" then lines[#lines + 1] = line; line = word else line = t2 end
      end
      if line ~= "" or para == "" then lines[#lines + 1] = line end
    end
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    local lh = gfx.texth + 3
    local bh = #lines * lh + 20
    local by = h - bh - 12
    col(COL.panel); gfx.rect(cx - 12, by, cw + 24, bh, 1)
    col(COL.accent); gfx.rect(cx - 12, by, 4, bh, 1)
    for i, l in ipairs(lines) do text(l, cx, by + 10 + (i - 1) * lh, COL.text, 2) end
    if button("×", cx + cw - 20, by + 6, 24, 22) or (clicked and hit(cx - 12, by, cw + 24, bh)) then msg = "" end
  end
  gfx.update()
end

local function loop()
  local ch = gfx.getchar()
  U.frame()
  reaper.SetExtState(SEC, "hub_alive", tostring(reaper.time_precise()), false)
  if V then
    if V.ST.job then V.ST.job() else V.ST.takes = V.selected_takes() end
  end
  demo_poll()
  if LD and LD.UI.pending then                                 -- mesure du niveau : lancée après l'affichage de « Mesure… »
    if LD.UI.drawn then local f = LD.UI.pending; LD.UI.pending = nil; LD.UI.drawn = false; f() else LD.UI.drawn = true end
  end
  local tid = reaper.GetExtState(SEC, "toast_id")
  if tid ~= "" and tid ~= LAST_TOAST then LAST_TOAST = tid; msg = reaper.GetExtState(SEC, "toast") end
  if ch < 0 or ch == 27 then return end
  local cap = gfx.mouse_cap
  if ch == 32 and page ~= "rec" then reaper.Main_OnCommand(40044, 0)
  elseif ch == 26 or (ch == 122 and cap & 4 == 4) then reaper.Main_OnCommand(cap & 8 == 8 and 40030 or 40029, 0)
  elseif ch == 25 or (ch == 121 and cap & 4 == 4) then reaper.Main_OnCommand(40030, 0) end
  if page == "rec" and (ch == 98 or ch == 66) then A.set("bips_play", A.get("bips_play", "0") == "1" and "0" or "1"); ch = 0 end   -- B : bips en répétition
  if page == "rec" and ch == 32 then ch = 0; if reaper.GetPlayState() & 1 == 1 then reaper.OnStopButton() else local D = adr_data(); rec_go(D, A.current(D.lines) or 1, "listen") end end
  if page == "rec" and (ch == 1818584692 or ch == 1919379572 or ch == 114 or ch == 82) then   -- ← → R
    local D = adr_data()
    local i = A.current(D.lines) or 1
    if ch == 1818584692 then rec_go(D, math.max(1, i - 1))
    elseif ch == 1919379572 then rec_go(D, math.min(#D.lines, i + 1))
    elseif reaper.GetPlayState() & 4 == 0 then rec_go(D, i, "rec") end
  end
  do                                                                -- en continu : à l'arrêt, on se place sur la réplique suivante
    local rec_now = reaper.GetPlayState() & 4 == 4
    if rec_now then REC_LAST = reaper.GetPlayPosition() end
    if REC_WAS and not rec_now and A.get("rec_mode", "line") == "free" and A.get("auto_next", "1") == "1" and REC_LAST then
      local D = adr_data()
      for k, l in ipairs(D.lines) do if l.pos >= REC_LAST - 0.2 then rec_go(D, k); break end end
    end
    REC_WAS = rec_now
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

LAST_TOAST = reaper.GetExtState(SEC, "toast_id")
if PODSUITE_TEST then PODSUITE_TEST.export_transcript, PODSUITE_TEST.export_chapters, PODSUITE_TEST.msg, PODSUITE_TEST.line_takes, PODSUITE_TEST.choose_take = export_transcript, export_chapters, function() return msg end, line_takes, choose_take end   -- tests automatiques
reaper.atexit(function() restore_record_mode(); reaper.DeleteExtState(SEC, "hub_alive", false) end)
find_ripple_cmds()
if reaper.GetExtState(SEC, "snap_default") ~= "2" then          -- par défaut : items aimantés les uns aux autres, pas à la grille
  if reaper.GetExtState(SEC, "snap_default") == "" or snap_on() then set_snap(true) end
  reaper.SetExtState(SEC, "snap_default", "2", true)
end
vocal_path = find_vocal()
do local ip, port = A.lan_ip(), P.web_port(); if ip and port then tablet_url = "http://" .. ip .. ":" .. port .. "/doublage.html" end end
if not DRAW[page] then page = "home" end
for _, pg in ipairs(PAGES) do if pg.id == page and not shown(pg) then page = "home" end end
loop()
