-- Toolbox - Controle du niveau.lua
-- Mesure le mix (bus master) AVANT l'export : loudness intégrée (LUFS), true peak, écart de volume (LRA),
-- compare à une norme (Podcast -16 LUFS, Spotify -14 LUFS), propose des pistes de correction
-- et peut corriger automatiquement avec un limiteur true peak placé en fin de chaîne du master.
-- Nécessite REAPER 6.71 ou plus récent (mesure par « dry run render »).

local TITLE = "Podcast & ADR Toolbox – Contrôle du niveau d'export"
local SECTION = "PODSUITE_LOUDNESS"
local SEP = package.config:sub(1, 1)
local scriptdir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])") or ""

local NORMS = {
  { name = "Podcast (Apple, autres)", target = -16, tol = 1, tp = -1 },
  { name = "Podcast (Spotify)", target = -14, tol = 1, tp = -1 },
}
local LIMDESC, LIMDESC_OLD = "Toolbox limiter", "Toolbox limiter"
local LIMFILE = "Toolbox limiter.jsfx"
local LRA_HIGH = 10                       -- au-delà, les écarts de volume se remarquent dans un podcast

local S = { norm = tonumber(reaper.GetExtState(SECTION, "norm")) or 1, scope = reaper.GetExtState(SECTION, "scope") }
if not NORMS[S.norm] then S.norm = 1 end
if S.scope ~= "sel" then S.scope = "all" end
local function save() reaper.SetExtState(SECTION, "norm", tostring(S.norm), true); reaper.SetExtState(SECTION, "scope", S.scope, true) end

---------------------------------------------------------------- Format des nombres (à la française)
local function num(v, d)
  local s = string.format("%." .. (d or 1) .. "f", math.abs(v)):gsub("%.", ",")
  if v < 0 and tonumber((s:gsub(",", "."))) ~= 0 then s = "−" .. s end
  return s
end
local function sgn(v, d) return (v > 0 and "+" or "") .. num(v, d) end

---------------------------------------------------------------- Actions « dry run » (retrouvées par leur nom)
local ACT_ALL = "Calculate loudness of master mix via dry run render"
local ACT_SEL = "Calculate loudness of master mix within time selection via dry run render"
local function action_text(id)
  if reaper.kbd_getTextFromCmd then
    local ok, t = pcall(reaper.kbd_getTextFromCmd, id, 0)
    if ok and type(t) == "string" then return t end
  end
  if reaper.CF_GetCommandText then
    local ok, t = pcall(reaper.CF_GetCommandText, 0, id)
    if ok and type(t) == "string" then return t end
  end
  return ""
end
local function find_action(name)
  local key = "id_" .. name
  local cached = tonumber(reaper.GetExtState(SECTION, key))
  if cached and action_text(cached) == name then return cached end
  for id = 40000, 45000 do
    if action_text(id) == name then reaper.SetExtState(SECTION, key, tostring(id), true); return id end
  end
end

---------------------------------------------------------------- Mesure
local function parse_stats(s)
  local t = {}
  for k, v in (s or ""):gmatch("([%a_]+):([^;]*);?") do
    local n = tonumber(v)
    if n then t[k:upper()] = n end
  end
  local m = { lufs = t.LUFSI, lra = t.LRA, peak = t.PEAK }
  m.tp = t.TRUEPEAK or t.TRUEPEAKDB or t.TP
  if not m.tp then
    for k, v in pairs(t) do if k:find("TRUE") and not k:find("POS") then m.tp = v end end
  end
  return m
end

local function has_timesel()
  local a, b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return b - a > 0.1
end

---------------------------------------------------------------- Limiteur sur le master
local function master() return reaper.GetMasterTrack(0) end
local function find_lim()
  local tr = master()
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, i, "")
    if name:find(LIMDESC, 1, true) or name:find(LIMDESC_OLD, 1, true) or name:find(LIMFILE, 1, true) or name:find("Toolbox limiter.jsfx", 1, true) then return i end
  end
  return -1
end

local function jsfx_name(FILE)
  -- ReaPack installe le plugin dans Effects/<dépôt>/<catégorie>/ ; on retrouve ce chemin depuis celui du script
  local res = reaper.GetResourcePath()
  local rel = scriptdir:sub(#res + 2):gsub("\\", "/")
  local inst = rel:match("^Scripts/(.*)$")
  local cands = {}
  if inst then cands[#cands + 1] = inst .. FILE end
  cands[#cands + 1] = FILE
  for _, c in ipairs(cands) do
    local f = io.open(res .. "/Effects/" .. c, "rb")
    if f then f:close(); return "JS:" .. c end
  end
  local src = io.open(scriptdir .. FILE, "rb") or io.open(scriptdir .. ".." .. SEP .. "Effects" .. SEP .. FILE, "rb")
  if src then
    local data = src:read("a"); src:close()
    reaper.RecursiveCreateDirectory(res .. SEP .. "Effects", 0)
    local f = io.open(res .. SEP .. "Effects" .. SEP .. FILE, "wb")
    if f then f:write(data); f:close(); return "JS:" .. FILE end
  end
end

local function ensure_lim()
  local tr = master()
  local fx = find_lim()
  if fx < 0 then
    local name = jsfx_name(LIMFILE)
    if not name then return nil end
    fx = reaper.TrackFX_AddByName(tr, name, false, -1)
    if fx < 0 then return nil end
    reaper.TrackFX_SetParam(tr, fx, 0, 0)
  end
  reaper.TrackFX_SetEnabled(tr, fx, true)
  return fx
end

local function lim_gain()
  local fx = find_lim()
  if fx < 0 then return nil end
  return (reaper.TrackFX_GetParam(master(), fx, 0)), reaper.TrackFX_GetEnabled(master(), fx)
end

local function fader_db()
  local v = reaper.GetMediaTrackInfo_Value(master(), "D_VOL")
  return 20 * math.log(math.max(v, 1e-9), 10)
end

-- Mesureur de true peak posé temporairement en fin de chaîne du master pendant la mesure.
-- Il voit le son après tous les effets du master ; le fader du master (appliqué après) est ajouté ensuite.
local METERFILE, METERDESC = "Toolbox TP meter.jsfx", "Toolbox true peak meter"
local function add_meter()
  local name = jsfx_name(METERFILE)
  if not name then return nil end
  local tr = master()
  local fx = reaper.TrackFX_AddByName(tr, name, false, -1)
  if fx < 0 then return nil end
  reaper.TrackFX_SetParam(tr, fx, 1, math.random(1, 999999))      -- remise à zéro
  reaper.TrackFX_SetParam(tr, fx, 0, -150)
  return fx
end
local function remove_meters()
  local tr = master()
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
    local _, name = reaper.TrackFX_GetFXName(tr, i, "")
    if name:find(METERDESC, 1, true) or name:find(METERFILE, 1, true) then reaper.TrackFX_Delete(tr, i) end
  end
end

-- renvoie la mesure, ou nil et un message d'erreur
local function measure()
  local sel = S.scope == "sel"
  if sel and not has_timesel() then return nil, "Aucune sélection temporelle : faites-en une, ou choisissez « Tout le projet »." end
  local id = find_action(sel and ACT_SEL or ACT_ALL)
  if not id then return nil, "Cette version de REAPER ne sait pas mesurer avant l'export : installez REAPER 7 (gratuit à essayer)." end
  remove_meters()
  local mfx = add_meter()
  local ok, stats = reaper.GetSetProjectInfo_String(0, "RENDER_STATS", tostring(id), false)
  local meter_tp
  if mfx then
    local v = reaper.TrackFX_GetParam(master(), mfx, 0)
    if v and v > -149 then meter_tp = v + fader_db() end
  end
  remove_meters()
  if not ok or not stats or stats == "" then return nil, "Mesure annulée." end
  local m = parse_stats(stats)
  if not m.lufs then return nil, "Mesure impossible (le projet est-il vide ou silencieux ?)." end
  m.raw = stats
  if not m.tp and meter_tp then m.tp = meter_tp; m.tp_src = "meter" end
  if m.tp then m.tp_src = m.tp_src or "reaper"
  elseif m.peak then m.tp, m.tp_src = m.peak, "sample" end           -- dernier recours : crête échantillon (dBFS)
  if not m.tp then return nil, "Mesure du true peak impossible : resynchronisez les paquets dans ReaPack." end
  return m
end

---------------------------------------------------------------- Diagnostic et pistes
local function verdict(m, N)
  local okL = math.abs(m.lufs - N.target) <= N.tol + 1e-6
  local okT = m.tp <= N.tp + 1e-6
  if m.tp_src == "sample" then okT = m.tp <= N.tp - 1 end           -- le true peak peut dépasser la crête échantillon
  return okL, okT
end

local function suggestions(m, N)
  local out = {}
  local okL, okT = verdict(m, N)
  local need = N.target - m.lufs
  local tp_after = m.tp + need
  if okL and okT then
    out[#out + 1] = "Rien à corriger : le mix respecte la norme. Exportez sans cocher de normalisation dans la fenêtre de rendu."
  else
    if not okL then
      if need > 0 then
        out[#out + 1] = string.format("Trop faible de %s LU : il faut monter le mix d'environ %s dB.", num(need), num(need))
      else
        out[#out + 1] = string.format("Trop fort de %s LU : il faut baisser le mix d'environ %s dB.", num(-need), num(-need))
      end
    end
    if tp_after > N.tp then
      local red = tp_after - N.tp
      if okL then
        out[#out + 1] = string.format("Les crêtes dépassent de %s dB : un limiteur true peak à %s dBTP les contient, sans changer le volume perçu.", num(m.tp - N.tp), num(N.tp))
      else
        out[#out + 1] = string.format("Après ce gain, les crêtes monteraient à %s dBTP (max %s) : un limiteur true peak doit les réduire d'environ %s dB.", sgn(tp_after), num(N.tp), num(red))
      end
      if red > 6 then
        out[#out + 1] = "C'est beaucoup : la voix risque de sonner écrasée. Mieux vaut d'abord régulariser le niveau (Vocal level & de-esser, « Niveau régulier » en Fort) ou ajouter un compresseur, puis remesurer."
      end
    elseif not okL then
      out[#out + 1] = string.format("Les crêtes resteront sous la limite (environ %s dBTP) : un simple gain suffit.", sgn(tp_after))
    end
    out[#out + 1] = "« Corriger automatiquement » place « Toolbox limiter » en fin de chaîne du master, règle le gain et le plafond, puis remesure."
  end
  if m.lra and m.lra > LRA_HIGH then
    out[#out + 1] = string.format("Écarts de volume importants (LRA %s LU) : certains passages seront trop faibles en voiture ou dans les transports. Régularisez la voix avec Vocal level & de-esser.", num(m.lra))
  end
  local fd = fader_db()
  if math.abs(fd) > 0.05 then
    out[#out + 1] = string.format("Le fader du master est à %s dB : il agit après le limiteur. La correction automatique le remet à 0 dB et reporte ce gain dans le limiteur.", sgn(fd))
  end
  if m.tp_src == "sample" then
    out[#out + 1] = "Remarque : le true peak n'a pas pu être mesuré ; c'est la crête échantillon (dBFS) qui est affichée. Le true peak pouvant être un peu plus haut, on exige 1 dB de marge."
  end
  if S.scope == "sel" then
    out[#out + 1] = "Mesure sur la sélection temporelle seulement : la valeur du fichier complet peut être différente."
  end
  return out
end

-- correction automatique : gain + limiteur, jusqu'à 4 mesures
local function auto_correct(N, on_step)
  local fx = ensure_lim()
  if not fx then return nil, "Plugin « Toolbox limiter » introuvable : resynchronisez les paquets dans ReaPack." end
  local tr = master()
  reaper.TrackFX_SetParam(tr, fx, 1, N.tp)
  local fd = fader_db()
  if math.abs(fd) > 0.05 then
    reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 1)
    reaper.TrackFX_SetParam(tr, fx, 0, math.max(-24, math.min(24, reaper.TrackFX_GetParam(tr, fx, 0) + fd)))
  end
  local m, err
  for it = 1, 4 do
    if on_step then on_step(it) end
    m, err = measure()
    if not m then return nil, err end
    local okL, okT = verdict(m, N)
    if okL and okT and math.abs(m.lufs - N.target) <= 0.3 then break end
    if it == 4 then break end
    local g = reaper.TrackFX_GetParam(tr, fx, 0)
    local ng = math.max(-24, math.min(24, g + (N.target - m.lufs)))
    if math.abs(ng - g) < 0.05 then break end
    reaper.TrackFX_SetParam(tr, fx, 0, ng)
  end
  return m
end

---------------------------------------------------------------- Interface
local W, H = 660, 680
local U = dofile(scriptdir .. "Toolbox_ui.lua")
U.init(TITLE, W, H)
local COL = {
  bg = { 0.10, 0.105, 0.12 }, panel = { 0.14, 0.15, 0.17 }, text = { 0.93, 0.93, 0.93 }, muted = { 0.6, 0.62, 0.67 },
  accent = { 0.97, 0.6, 0.22 }, line = { 0.24, 0.25, 0.28 }, ok = { 0.3, 0.8, 0.5 }, bad = { 0.95, 0.42, 0.32 },
}
local function col(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function fonts()
  gfx.setfont(1, "Arial", 15); gfx.setfont(2, "Arial", 13); gfx.setfont(3, "Arial", 19, string.byte("b"))
  gfx.setfont(4, "Arial", 13, string.byte("b")); gfx.setfont(5, "Arial", 26, string.byte("b"))
end
fonts()
local function text(s, x, y, c, f) gfx.setfont(f or 1); col(c or COL.text); gfx.x, gfx.y = x, y; gfx.drawstr(s) end
local function wrap(s, x, y, w, c, f)
  gfx.setfont(f or 2); col(c or COL.text)
  local line = ""
  local lh = gfx.texth + 3
  for word in s:gmatch("%S+") do
    local t = line == "" and word or (line .. " " .. word)
    if gfx.measurestr(t) > w and line ~= "" then
      gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh; line = word
    else line = t end
  end
  if line ~= "" then gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh end
  return y
end
local function hit(x, y, w, h) return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h end
local clicked, mouse_was = false, false
local function button(label, x, y, w, h, primary, active)
  local over = hit(x, y, w, h)
  if primary or active then col(COL.accent, over and 1 or 0.88) else col(COL.panel) end
  gfx.rect(x, y, w, h, 1)
  if not (primary or active) then col(COL.line); gfx.rect(x, y, w, h, 0) end
  gfx.setfont(4); local tw = gfx.measurestr(label)
  if primary or active then gfx.set(0.1, 0.06, 0.02) else col(COL.text) end
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - gfx.texth) / 2; gfx.drawstr(label)
  return clicked and over
end

local UI = { m = nil, msg = "", pending = nil, busy = false }
local function set_msg(s) UI.msg = s end

local function do_measure()
  UI.busy = true; set_msg("Mesure en cours (REAPER lit tout le mix, sans exporter)…")
  UI.pending = function()
    local m, err = measure()
    UI.busy = false
    if m then UI.m = m; set_msg("") else set_msg(err) end
  end
end

local function do_correct()
  UI.busy = true; set_msg("Correction en cours : réglage du limiteur et nouvelles mesures…")
  UI.pending = function()
    local N = NORMS[S.norm]
    reaper.Undo_BeginBlock()
    local m, err = auto_correct(N)
    reaper.Undo_EndBlock("Toolbox : correction du niveau d'export", -1)
    UI.busy = false
    if m then
      UI.m = m
      local okL, okT = verdict(m, N)
      local g = lim_gain() or 0
      set_msg(okL and okT and string.format("Corrigé : gain du limiteur %s dB. Vous pouvez exporter.", sgn(g))
        or "Pas tout à fait dans la norme après correction : voir les pistes ci-dessus.")
    else set_msg(err) end
  end
end

local function remove_lim()
  local fx = find_lim()
  if fx < 0 then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_Delete(master(), fx)
  reaper.Undo_EndBlock("Toolbox : limiteur retiré", -1)
  UI.m = nil
  set_msg("Limiteur retiré du master. Remesurez.")
end

local function tile(x, y, w, h, label, value, sub, ok)
  col(COL.panel); gfx.rect(x, y, w, h, 1)
  col(ok == nil and COL.line or (ok and COL.ok or COL.bad)); gfx.rect(x, y, 4, h, 1)
  text(label, x + 14, y + 10, COL.muted, 2)
  text(value, x + 14, y + 28, ok == nil and COL.text or (ok and COL.ok or COL.bad), 5)
  text(sub, x + 14, y + 62, COL.muted, 2)
end

local function draw()
  col(COL.bg); gfx.rect(0, 0, U.W(), U.H(), 1)
  local x, w = 24, W - 48
  text("Contrôle du niveau d'export", x, 18, COL.text, 3)
  text("Mesure le mix du master tel qu'il sera exporté, avant d'exporter.", x, 46, COL.muted, 2)
  local y = 80
  text("Norme visée", x, y + 6, COL.text, 1)
  local bw = 190
  for i, N in ipairs(NORMS) do
    if button(N.name, x + w - (#NORMS - i + 1) * (bw + 6) + 6, y, bw, 28, false, S.norm == i) and not UI.busy then S.norm = i; save() end
  end
  local N = NORMS[S.norm]
  text(string.format("%s LUFS intégrés (± %s LU) · true peak max %s dBTP", num(N.target, 0), num(N.tol, 0), num(N.tp, 0)), x + w - 2 * (bw + 6) + 6, y + 36, COL.muted, 2)
  y = y + 66
  text("Portion mesurée", x, y + 6, COL.text, 1)
  if button("Tout le projet", x + w - 2 * (bw + 6) + 6, y, bw, 28, false, S.scope == "all") and not UI.busy then S.scope = "all"; save() end
  if button("Sélection temporelle", x + w - bw, y, bw, 28, false, S.scope == "sel") and not UI.busy then S.scope = "sel"; save() end
  y = y + 46
  if button(UI.busy and "Mesure…" or (UI.m and "Remesurer" or "Mesurer"), x, y, 200, 36, true) and not UI.busy then do_measure() end
  local g, en = lim_gain()
  if g then
    text(string.format("Toolbox limiter sur le master : gain %s dB%s", sgn(g), en and "" or " (désactivé)"), x + 214, y + 4, COL.muted, 2)
    if button("Retirer le limiteur", x + 214, y + 20, 150, 22) and not UI.busy then remove_lim() end
  end
  y = y + 52
  col(COL.line); gfx.line(x, y, x + w, y)
  y = y + 16
  local m = UI.m
  if not m then
    y = wrap("Cliquez sur « Mesurer ». REAPER lit tout le mix (plus vite que le temps réel) sans créer de fichier, puis l'outil compare le résultat à la norme choisie et propose quoi corriger.", x, y, w, COL.muted, 2)
  else
    local okL, okT = verdict(m, N)
    local tw = (w - 24) / 3
    tile(x, y, tw, 84, "Loudness intégrée", num(m.lufs) .. " LUFS", string.format("visé : %s à %s", num(N.target - N.tol, 0), num(N.target + N.tol, 0)), okL)
    tile(x + tw + 12, y, tw, 84, m.tp_src == "sample" and "Crête (échantillon)" or "True peak", sgn(m.tp) .. (m.tp_src == "sample" and " dBFS" or " dBTP"), m.tp_src == "sample" and ("max : " .. num(N.tp - 1, 0) .. " dBFS (marge)") or ("max : " .. num(N.tp, 0) .. " dBTP"), okT)
    tile(x + 2 * (tw + 12), y, tw, 84, "Écart de volume (LRA)", m.lra and (num(m.lra) .. " LU") or "—", "bas = voix régulière", m.lra and (m.lra <= LRA_HIGH) or nil)
    y = y + 100
    if okL and okT then text("✓  Prêt pour l'export", x, y, COL.ok, 3) else text("À corriger avant l'export", x, y, COL.bad, 3) end
    y = y + 34
    text("PISTES", x, y, COL.muted, 4)
    y = y + 20
    for _, s in ipairs(suggestions(m, N)) do
      col(COL.accent); gfx.rect(x + 2, y + 6, 5, 5, 1)
      y = wrap(s, x + 16, y, w - 16, COL.text, 2) + 4
    end
    if not (okL and okT) then
      y = y + 6
      if button("Corriger automatiquement", x, y, 230, 34, true) and not UI.busy then do_correct() end
      y = y + 44
    end
  end
  if UI.msg ~= "" then wrap(UI.msg, x, H - 34, w, COL.muted, 2) end
  gfx.update()
end

local function loop()
  local ch = gfx.getchar()
  U.frame()
  if ch < 0 or ch == 27 then save(); gfx.quit(); return end
  local cap = gfx.mouse_cap
  if ch == 32 then reaper.Main_OnCommand(40044, 0)
  elseif ch == 26 or (ch == 122 and cap & 4 == 4) then reaper.Main_OnCommand(cap & 8 == 8 and 40030 or 40029, 0)
  elseif ch == 25 or (ch == 121 and cap & 4 == 4) then reaper.Main_OnCommand(40030, 0) end
  local down = cap & 1 == 1
  clicked = down and not mouse_was
  mouse_was = down
  if UI.pending and UI.drawn then local f = UI.pending; UI.pending = nil; UI.drawn = false; f()
  elseif UI.pending then UI.drawn = true end            -- on affiche « Mesure en cours » avant de lancer la mesure
  draw()
  if PODSUITE_TEST then PODSUITE_TEST.UI, PODSUITE_TEST.correct, PODSUITE_TEST.sugg = UI, do_correct, suggestions end   -- tests automatiques
reaper.defer(loop)
end
if PODSUITE_TEST then PODSUITE_TEST.UI, PODSUITE_TEST.correct, PODSUITE_TEST.sugg = UI, do_correct, suggestions end   -- tests automatiques
reaper.defer(loop)
