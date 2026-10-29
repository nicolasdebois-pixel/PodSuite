-- PodSuite - Serveur.lua
-- À laisser tourner pendant le travail (bouton de barre d'outils) :
--  • publie la transcription du projet actif vers la page podsuite.html ;
--  • enregistre les passages barrés et les suggestions ignorées depuis la page ;
--  • construit le MONTAGE dans REAPER : une piste « ✂ Intervenant » par intervenant, reconstruite
--    depuis les rushes (jamais modifiés) à chaque changement. Les coupes sont placées dans les silences.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")

local XF = 0.012                 -- fondu enchaîné à chaque coupe (12 ms)
local cur_fn, data, datafile = nil, nil, nil
local last_rev, last_ver, last_listen, hb, last_hb = nil, nil, nil, 0, 0
local pending_save, pending_build, dirty_at = false, false, 0
local env, envstart = {}, 0
local warned_source = false

---------------------------------------------------------------- Chargement
local ENV_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENV_LV = {}
for i = 1, #ENV_ALPHA do ENV_LV[ENV_ALPHA:sub(i, i)] = i - 1 end

local qlevel = 20                 -- niveau (1,25 dB par pas) sous lequel on considère qu'il y a une pause
local function decode_env()
  env = {}
  local s = data and data.env or ""
  for i = 1, #s do env[i] = ENV_LV[s:sub(i, i)] or 0 end
  envstart = data and (data.envstart or data.start) or 0
  local sorted = {}
  for i = 1, #env do sorted[i] = env[i] end
  table.sort(sorted)
  local floor = sorted[math.max(1, math.floor(#sorted * 0.1))] or 0
  qlevel = floor + 8                -- ≈ 10 dB au-dessus du bruit de fond
end

local function first_word_at(t)
  local w = data.words
  local lo, hi = 1, #w + 1
  while lo < hi do local m = (lo + hi) // 2; if w[m].a < t then lo = m + 1 else hi = m end end
  return lo
end

local function montage_tracks_exist()
  for i = 0, reaper.CountTracks(0) - 1 do
    local _, ext = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_EXT:PODSUITE", "", false)
    if ext:sub(1, 8) == "montage|" then return true end
  end
  return false
end

-- republish = true seulement au changement de projet : une nouvelle version venue d'ailleurs
-- (fin de transcription) est simplement relue, sinon deux serveurs se relanceraient sans fin.
local function load_project(republish)
  local _, fn, ddir = P.project()
  cur_fn = fn
  if fn then
    datafile = ddir .. P.SEP .. "transcript.json"
    local ok, d = pcall(P.json_decode, P.read_file(datafile) or "")
    data = (ok and type(d) == "table" and d.words) and d or nil
  else
    datafile, data = nil, nil
  end
  if data then
    for _, c in ipairs(data.clicks or {}) do c.idx = first_word_at(c.t) end
    decode_env()
    if republish then P.publish(data, nil) end
    local has = false
    for _ in pairs((data.edits or {}).strikes or {}) do has = true; break end
    pending_build = has or montage_tracks_exist()
    if not pending_build then P.write_file(P.www_dir() .. P.SEP .. "podsuite_map.json", "{\"segs\":[]}"); reaper.SetExtState(P.SECTION, "mapver", tostring(os.clock()), false) end
  else
    if republish then P.publish({ format = 2, empty = true, project = fn and fn:match("([^/\\]+)$") or "" }, nil) end
  end
  last_ver = reaper.GetExtState(P.SECTION, "version")
  last_rev = reaper.GetExtState(P.SECTION, "edits_rev")
end

-- « S12-45.80-81~I3.7 » : mots barrés (plages d'index) ; suggestions ignorées (index de clic)
local function parse_edits(s)
  local strikes, ignored = {}, {}
  local S = s:match("S([^~]*)") or ""
  local I = s:match("I([^~]*)") or ""
  for a, b in S:gmatch("(%d+)%-(%d+)") do strikes[#strikes + 1] = { tonumber(a), tonumber(b) } end
  for c in I:gmatch("%d+") do ignored[#ignored + 1] = tonumber(c) end
  return { strikes = strikes, ignored = ignored }
end

---------------------------------------------------------------- Calcul des coupes
-- Point le plus calme (énergie lissée sur 30 ms) entre a et b ; milieu de la zone calme.
local function quietest(a, b)
  if #env == 0 or b - a < 0.015 then return (a + b) / 2 end
  local f0 = math.max(2, math.floor((a - envstart) * 100) + 1)
  local f1 = math.min(#env - 1, math.floor((b - envstart) * 100) + 1)
  if f1 < f0 then return (a + b) / 2 end
  local v, best = {}, math.huge
  for f = f0, f1 do v[f] = env[f - 1] + env[f] + env[f + 1]; if v[f] < best then best = v[f] end end
  local runs, bestLen, bestMid = 0, -1, (a + b) / 2
  local f = f0
  while f <= f1 do
    if v[f] <= best + 2 then
      local j = f
      while j + 1 <= f1 and v[j + 1] <= best + 2 do j = j + 1 end
      if j - f > bestLen then bestLen = j - f; bestMid = envstart + ((f + j) / 2 - 1) * 0.01 + 0.005 end
      f = j + 1
    else f = f + 1 end
  end
  return bestMid
end

-- Dernière pause (≥ 50 ms sous le seuil) entre a et b : renvoie début, fin — ou nil.
-- La DERNIÈRE, parce qu'elle précède directement le mot suivant (les silences internes d'un mot,
-- comme la tenue d'un « p » ou d'un « t », sont plus courts ou plus tôt).
local function last_pause(a, b)
  if #env == 0 or b <= a then return nil end
  local f0 = math.max(2, math.floor((a - envstart) * 100) + 1)
  local f1 = math.min(#env - 1, math.floor((b - envstart) * 100) + 1)
  local best, f = nil, f0
  while f <= f1 do
    if env[f] <= qlevel then
      local j = f
      while j + 1 <= f1 and env[j + 1] <= qlevel do j = j + 1 end
      if j - f + 1 >= 5 then best = { envstart + (f - 1) * 0.01, envstart + j * 0.01 } end
      f = j + 1
    else f = f + 1 end
  end
  return best
end

-- Point de coupe juste AVANT le mot qui commence vers « est » :
-- dans la pause qui le précède s'il y en a une, sinon au point le plus calme tout près de l'estimation.
local function cut_before(est, lo)
  local p = last_pause(math.max(lo, est - 0.6), est + 0.08)
  if p then return math.max(p[1], p[2] - 0.02) end
  return quietest(math.max(lo, est - 0.04), est + 0.04)
end

local function compute_cuts()
  local w, cuts = data.words, {}
  local st = {}
  for _, r in ipairs((data.edits or {}).strikes or {}) do
    for i = r[1] + 1, math.min(#w, r[2] + 1) do st[i] = true end      -- index JS (0) → Lua (1)
  end
  local i = 1
  while i <= #w do
    if st[i] then
      local j = i
      while j + 1 <= #w and st[j + 1] do j = j + 1 end
      -- de juste avant le premier mot barré jusqu'à juste avant le mot gardé suivant :
      -- la pause qui précédait le passage est conservée, celle qui le suivait disparaît avec lui
      local sa, eb
      if i == 1 then sa = data.start
      else sa = cut_before(w[i].a, w[i - 1].a + 0.06) end
      local endFrom = w[j].a + 0.06
      for _, c in ipairs(data.clicks or {}) do
        if c.n ~= 2 and c.idx == j + 1 then endFrom = math.max(endFrom, c.e) end
      end
      if j == #w then eb = data.stop
      else eb = math.max(cut_before(w[j + 1].a, endFrom), endFrom) end
      if eb > sa + 0.02 then cuts[#cuts + 1] = { sa, eb } end
      i = j + 1
    else i = i + 1 end
  end
  -- le son du clicker est toujours retiré
  for _, c in ipairs(data.clicks or {}) do cuts[#cuts + 1] = { c.t - 0.02, c.e } end
  table.sort(cuts, function(x, y) return x[1] < y[1] end)
  local merged = {}
  for _, c in ipairs(cuts) do
    local a, b = math.max(data.start, c[1]), math.min(data.stop, c[2])
    if b > a then
      local m = merged[#merged]
      if m and a <= m[2] + 0.03 then m[2] = math.max(m[2], b) else merged[#merged + 1] = { a, b } end
    end
  end
  local segs, t = {}, data.start
  for _, c in ipairs(merged) do
    if c[1] - t > 0.01 then segs[#segs + 1] = { t, c[1] } end
    t = c[2]
  end
  if data.stop - t > 0.01 then segs[#segs + 1] = { t, data.stop } end
  return segs
end

---------------------------------------------------------------- Construction du montage
local function track_by_guid(g)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == g then return tr end
  end
end

local function montage_track(sp, src)
  local key = "montage|" .. sp.guid
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, ext = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:PODSUITE", "", false)
    if ext == key then return tr end
  end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "✂ " .. (sp.name ~= "" and sp.name or "Montage"), true)
  reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:PODSUITE", key, true)
  local col = reaper.GetTrackColor(src)
  if col ~= 0 then reaper.SetTrackColor(tr, col) end
  return tr
end

local function apply_listen(mode)
  for _, sp in ipairs(data and data.speakers or {}) do
    local src = track_by_guid(sp.guid)
    if src then reaper.SetMediaTrackInfo_Value(src, "B_MUTE", mode == "edit" and 1 or 0) end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, ext = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:PODSUITE", "", false)
    if ext:sub(1, 8) == "montage|" then reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", mode == "edit" and 0 or 1) end
  end
end

local function build_montage()
  local segs = compute_cuts()
  reaper.PreventUIRefresh(1)
  local skipped = false
  for _, sp in ipairs(data.speakers or {}) do
    local src = track_by_guid(sp.guid)
    if src then
      local mt = montage_track(sp, src)
      for k = reaper.CountTrackMediaItems(mt) - 1, 0, -1 do reaper.DeleteTrackMediaItem(mt, reaper.GetTrackMediaItem(mt, k)) end
      local items = {}
      for k = 0, reaper.CountTrackMediaItems(src) - 1 do
        local it = reaper.GetTrackMediaItem(src, k)
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        local tk = reaper.GetActiveTake(it)
        if tk and pos < data.stop and pos + len > data.start and reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
          local file = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(tk), "")
          if file and file ~= "" then
            items[#items + 1] = {
              pos = pos, len = len, file = file, ivol = reaper.GetMediaItemInfo_Value(it, "D_VOL"),
              offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"), rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"),
              tvol = reaper.GetMediaItemTakeInfo_Value(tk, "D_VOL"), pan = reaper.GetMediaItemTakeInfo_Value(tk, "D_PAN"),
              chan = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE"),
            }
          else skipped = true end
        end
      end
      local dst = data.start
      for _, s in ipairs(segs) do
        local a, b = s[1], s[2]
        for _, it in ipairs(items) do
          local x0, x1 = math.max(a, it.pos), math.min(b, it.pos + it.len)
          if x1 > x0 + 0.001 then
            local e0 = (x0 == a) and math.min(XF / 2, x0 - it.pos) or 0
            local e1 = (x1 == b) and math.min(XF / 2, it.pos + it.len - x1) or 0
            local ni = reaper.AddMediaItemToTrack(mt)
            reaper.SetMediaItemInfo_Value(ni, "D_POSITION", dst + (x0 - a) - e0)
            reaper.SetMediaItemInfo_Value(ni, "D_LENGTH", (x1 - x0) + e0 + e1)
            reaper.SetMediaItemInfo_Value(ni, "D_FADEINLEN", math.max(0.002, 2 * e0))
            reaper.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", math.max(0.002, 2 * e1))
            reaper.SetMediaItemInfo_Value(ni, "D_VOL", it.ivol)
            local tk = reaper.AddTakeToMediaItem(ni)
            reaper.SetMediaItemTake_Source(tk, reaper.PCM_Source_CreateFromFile(it.file))
            reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", it.offs + (x0 - e0 - it.pos) * it.rate)
            reaper.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", it.rate)
            reaper.SetMediaItemTakeInfo_Value(tk, "D_VOL", it.tvol)
            reaper.SetMediaItemTakeInfo_Value(tk, "D_PAN", it.pan)
            reaper.SetMediaItemTakeInfo_Value(tk, "I_CHANMODE", it.chan)
          end
        end
        dst = dst + (b - a)
      end
    end
  end
  local mode = reaper.GetExtState(P.SECTION, "listen")
  if mode == "" then mode = "edit"; reaper.SetExtState(P.SECTION, "listen", mode, false) end
  apply_listen(mode); last_listen = mode
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.MarkProjectDirty(0)

  -- carte rushes → montage pour la page (karaoké et déplacements)
  local parts, d = {}, data.start
  for _, s in ipairs(segs) do
    parts[#parts + 1] = string.format("[%.3f,%.3f,%.3f]", s[1], s[2], d)
    d = d + (s[2] - s[1])
  end
  P.write_file(P.www_dir() .. P.SEP .. "podsuite_map.json", '{"segs":[' .. table.concat(parts, ",") .. "]}")
  reaper.SetExtState(P.SECTION, "mapver", tostring(reaper.time_precise()), false)
  if skipped and not warned_source then
    warned_source = true
    reaper.MB("Certains items des rushes n'ont pas de fichier audio direct (item découpé en section, inversé…).\nIls ne figurent pas dans le montage : appliquez « Glue » sur ces items puis relancez.", "PodSuite", 0)
  end
end

---------------------------------------------------------------- Boucle
local function save_now()
  if not (data and datafile) then return end
  local js = P.json_encode(data)
  P.write_file(datafile, js)
  P.write_file(P.www_data(), js)
end

local ME = tostring(reaper.time_precise()) .. "-" .. tostring(math.random(1, 1e9))
local function loop()
  -- un seul serveur à la fois : le dernier lancé prend la main, l'ancien s'arrête
  if reaper.GetExtState(P.SECTION, "server") ~= ME then return end
  local _, fn = reaper.EnumProjects(-1)
  if fn ~= cur_fn then load_project(true) end
  local ver = reaper.GetExtState(P.SECTION, "version")
  if ver ~= last_ver then load_project(false) end

  local now = reaper.time_precise()
  local rev = reaper.GetExtState(P.SECTION, "edits_rev")
  if rev ~= last_rev then
    last_rev = rev
    if data and datafile then
      data.edits = parse_edits(reaper.GetExtState(P.SECTION, "edits"))
      pending_save = true; pending_build = true; dirty_at = now
    end
  end
  if pending_build and data and now - dirty_at > 0.2 then
    pending_build = false
    build_montage()
  end
  local listen = reaper.GetExtState(P.SECTION, "listen")
  if data and listen ~= "" and listen ~= last_listen and montage_tracks_exist() then
    last_listen = listen
    reaper.PreventUIRefresh(1); apply_listen(listen); reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
  end

  if now - last_hb > 1 then
    last_hb = now; hb = hb + 1
    reaper.SetExtState(P.SECTION, "hb", tostring(hb), false)
    if pending_save then pending_save = false; save_now() end
  end
  reaper.defer(loop)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  if pending_save then save_now() end
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
  reaper.DeleteExtState(P.SECTION, "hb", false)
end)

P.install_page()
reaper.SetExtState(P.SECTION, "server", ME, false)
load_project(true)
loop()
