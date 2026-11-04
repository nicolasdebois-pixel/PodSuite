-- Toolbox_loudness.lua — moteur du contrôle du niveau d'export (mesure, diagnostic, correction).
-- Utilisé par la page « Export » de la fenêtre principale et par la fenêtre « Contrôle du niveau ».
-- Mesure le mix (bus master) AVANT l'export : loudness intégrée (LUFS), true peak, écart de volume (LRA),
-- compare à une norme (Podcast -16 LUFS, Spotify -14 LUFS), propose des pistes de correction
-- et peut corriger automatiquement avec un limiteur true peak placé en fin de chaîne du master.
-- Nécessite REAPER 6.71 ou plus récent (mesure par « dry run render »).

local TITLE = "Podcast & ADR Toolbox – Contrôle du niveau d'export"
local SECTION = "PODSUITE_LOUDNESS"
local SEP = package.config:sub(1, 1)
local scriptdir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])")) or ""

local NORMS = {
  { name = "Podcast (Apple, autres)", target = -16, tol = 1, tp = -1 },
  { name = "Podcast (Spotify)", target = -14, tol = 1, tp = -1 },
}
local LIMDESC, LIMDESC_OLD = "Toolbox limiter", "PodSuite limiter"
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


return {
  TITLE = TITLE, NORMS = NORMS, S = S, save = save, num = num, sgn = sgn, LRA_HIGH = LRA_HIGH,
  UI = UI, set_msg = set_msg, measure = measure, verdict = verdict, suggestions = suggestions,
  do_measure = do_measure, do_correct = do_correct, remove_lim = remove_lim, lim_gain = lim_gain, has_timesel = has_timesel,
}
