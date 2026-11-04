-- Toolbox_adr.lua — doublage (ADR) : personnages, répliques, bips, enregistrement.
-- Organisation dans REAPER (tout reste éditable à la main) :
--   • piste « @Nom »        : les répliques du personnage = items vides, texte dans les notes de l'item ;
--   • piste « Prises - Nom » : juste en dessous, l'enregistrement du comédien (une prise par passage) ;
--   • piste « Bips »         : un double bip avant la réplique en cours, audible seulement pendant l'enregistrement.
-- Signes de détection dans le texte : (r) respiration · (b) bouche fermée · (rire) · (s) soupir.
local P = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "Toolbox_lib.lua")
local A = {}
A.P = P
A.SEC = "TOOLBOX_ADR"
A.PREFIX = "@"
A.REC_PREFIX = "Prises - "
A.BIPS = "Bips"
A.PALETTE = { { 255, 107, 107 }, { 77, 171, 247 }, { 105, 219, 124 }, { 255, 212, 59 }, { 204, 93, 232 }, { 255, 146, 43 }, { 56, 217, 169 }, { 240, 101, 149 } }

function A.get(k, d) local v = reaper.GetExtState(A.SEC, k); if v == "" then return d end return v end
function A.set(k, v) reaper.SetExtState(A.SEC, k, tostring(v), true) end

---------------------------------------------------------------- Pistes
local function track_name(tr) local _, n = reaper.GetTrackName(tr); return n end
function A.find_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_name(tr) == name then return tr, i end
  end
end
local function insert_track(idx, name, color)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  if color then reaper.SetTrackColor(tr, color) end
  return tr
end

-- personnages, dans l'ordre des pistes
function A.characters()
  local list = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local n = track_name(tr)
    if n:sub(1, #A.PREFIX) == A.PREFIX then
      local who = n:sub(#A.PREFIX + 1):match("^%s*(.-)%s*$")
      if who == "" then who = "?" end
      local c = reaper.GetTrackColor(tr)
      local r, g, b = 154, 170, 221
      if c ~= 0 then r, g, b = reaper.ColorFromNative(c) end
      list[#list + 1] = { name = who, track = tr, index = i, color = { r, g, b }, hex = string.format("%02x%02x%02x", r, g, b) }
    end
  end
  return list
end

-- piste des répliques du personnage (créée au besoin, avec sa piste de prises juste en dessous)
function A.char_track(name)
  for _, c in ipairs(A.characters()) do                      -- « marc » et « MARC » : même personnage
    if c.name:lower() == name:lower() then return c.track end
  end
  local full = A.PREFIX .. name
  local n = #A.characters()
  local c = A.PALETTE[(n % #A.PALETTE) + 1]
  local col = reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000
  local idx = reaper.CountTracks(0)
  local _, bi = A.find_track(A.BIPS)
  if bi then idx = bi end                                     -- la piste Bips reste en dernier
  tr = insert_track(idx, full, col)
  A.rec_track(name)
  return tr
end

function A.rec_track(name)
  local full = A.REC_PREFIX .. name
  local tr = A.find_track(full)
  if tr then return tr end
  local ct, ci = A.find_track(A.PREFIX .. name)
  local idx = ci and ci + 1 or reaper.CountTracks(0)
  tr = insert_track(idx, full, ct and reaper.GetTrackColor(ct) or nil)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)            -- le comédien s'entend
  return tr
end

---------------------------------------------------------------- Répliques
local function clean(s) return (s or ""):gsub("[\r\n\t]+", " "):match("^%s*(.-)%s*$") end
function A.item_text(it) local _, n = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false); return clean(n) end
function A.item_vo(it) local _, n = reaper.GetSetMediaItemInfo_String(it, "P_EXT:ADR_VO", "", false); return clean(n) end
function A.guid(it) local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false); return g end

-- toutes les répliques (ou celles d'un personnage), triées dans le temps
function A.lines(focus)
  local out = {}
  for _, ch in ipairs(A.characters()) do
    if not focus or focus == "" or focus == ch.name then
      for j = 0, reaper.CountTrackMediaItems(ch.track) - 1 do
        local it = reaper.GetTrackMediaItem(ch.track, j)
        local txt = A.item_text(it)
        if txt ~= "" and reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
          out[#out + 1] = { item = it, who = ch.name, char = ch, text = txt, vo = A.item_vo(it),
            pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"), len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH") }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.pos < b.pos end)
  for i, l in ipairs(out) do l.n = i end
  return out
end

function A.add_line(name, pos, len, text, vo)
  local tr = A.char_track(name)
  local it = reaper.AddMediaItemToTrack(tr)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", len)
  reaper.GetSetMediaItemInfo_String(it, "P_NOTES", text, true)
  if vo and vo ~= "" and vo ~= text then reaper.GetSetMediaItemInfo_String(it, "P_EXT:ADR_VO", vo, true) end
  return it
end

-- répliques sélectionnées (items vides ou non, sur une piste « @ »)
function A.selected_lines()
  local out = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local n = track_name(reaper.GetMediaItem_Track(it))
    if n:sub(1, #A.PREFIX) == A.PREFIX then out[#out + 1] = it end
  end
  return out
end

function A.assign(items, name)
  local tr = A.char_track(name)
  for _, it in ipairs(items) do reaper.MoveMediaItemToTrack(it, tr) end
  return #items
end

---------------------------------------------------------------- SRT
local function srt_time(h, m, s, ms) return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / (10 ^ #ms) end
-- renvoie { {pos, len, who|nil, text}, ... }
function A.parse_srt(txt)
  txt = txt:gsub("^\239\187\191", ""):gsub("\r", ""):gsub("\n[ \t]+\n", "\n\n")
  local out = {}
  for block in (txt .. "\n\n"):gmatch("(.-)\n\n+") do
    local h1, m1, s1, ms1, h2, m2, s2, ms2 = block:match("(%d+):(%d+):(%d+)[,%.](%d+)%s*%-%->%s*(%d+):(%d+):(%d+)[,%.](%d+)")
    local body = block:match("%-%->[^\n]*\n(.*)")
    if h1 and body then
      local lines = {}
      for raw in body:gmatch("[^\n]+") do
        local l = raw:gsub("<[^>]->", ""):gsub("{[^}]-}", ""):match("^%s*(.-)%s*$")
        if l ~= "" then lines[#lines + 1] = l end
      end
      local text = table.concat(lines, " / ")
      if text ~= "" then
        local who, rest = text:match("^([^:/]+):%s*(.+)$")
        if who and #who <= 24 and not who:find("%d%d") then text = rest; who = who:match("^%s*(.-)%s*$") else who = nil end
        local a, b = srt_time(h1, m1, s1, ms1), srt_time(h2, m2, s2, ms2)
        if b > a then out[#out + 1] = { pos = a, len = b - a, who = who, text = text } end
      end
    end
  end
  return out
end

---------------------------------------------------------------- Bips
-- fichier son du bip (1 kHz, 150 ms), créé une fois dans le dossier de la boîte à outils
function A.bip_file()
  local path = P.RES .. P.SEP .. "adr_bip.wav"
  if P.exists(path) then return path end
  reaper.RecursiveCreateDirectory(P.RES, 0)
  local sr, n = 48000, 7200
  local f = io.open(path, "wb"); if not f then return nil end
  local bytes = n * 2
  f:write("RIFF", string.pack("<I4", 36 + bytes), "WAVE", "fmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sr, sr * 2, 2, 16), "data", string.pack("<I4", bytes))
  local t = {}
  for i = 0, n - 1 do
    local env = math.min(1, i / 240, (n - 1 - i) / 240)            -- 5 ms de fondu : pas de clic
    t[#t + 1] = math.floor(0.25 * env * math.sin(2 * math.pi * 1000 * i / sr) * 32767 + 0.5)
    if #t == 1200 then f:write(string.pack("<" .. string.rep("i2", #t), table.unpack(t))); t = {} end
  end
  if #t > 0 then f:write(string.pack("<" .. string.rep("i2", #t), table.unpack(t))) end
  f:close()
  return path
end

-- les deux bips sont placés à -1 s et -0,5 s du début : « bip, bip, top » — on parle au troisième temps
A.BIP_TIMES = { 1.0, 0.5 }

-- piste « Bips » : un double bip, seulement avant la réplique en cours d'enregistrement
function A.build_bips(line)
  local tr = A.find_track(A.BIPS)
  if not tr then tr = insert_track(reaper.CountTracks(0), A.BIPS, reaper.ColorToNative(90, 90, 96) | 0x1000000) end
  for j = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do reaper.DeleteTrackMediaItem(tr, reaper.GetTrackMediaItem(tr, j)) end
  if not line then return tr end
  local file = A.bip_file(); if not file then return tr end
  local src = reaper.PCM_Source_CreateFromFile(file)
  for _, k in ipairs(A.BIP_TIMES) do
    local t = line.pos - k
    if t >= 0 then
      local it = reaper.AddMediaItemToTrack(tr)
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", t)
      reaper.SetMediaItemInfo_Value(it, "D_LENGTH", 0.15)
      reaper.SetMediaItemInfo_Value(it, "C_LOCK", 1)
      local tk = reaper.AddTakeToMediaItem(it)
      reaper.SetMediaItemTake_Source(tk, src)
    end
  end
  return tr
end

---------------------------------------------------------------- Actions REAPER retrouvées par leur nom
local CMD = {}
function A.cmd(key)
  if CMD[key] ~= nil then return CMD[key] or nil end
  local saved = tonumber(A.get("cmd_" .. key, ""))
  if saved then CMD[key] = saved > 0 and saved or false; return CMD[key] or nil end
  local want = {
    punch = function(n) return n:find("record mode", 1, true) and n:find("time selection", 1, true) and n:find("auto", 1, true) and n:find("punch", 1, true) end,
    normal = function(n) return n:find("record mode", 1, true) and n:find("normal", 1, true) end,
  }
  local found = 0
  if reaper.kbd_getTextFromCmd and want[key] then
    for id = 40000, 45000 do
      local ok, name = pcall(reaper.kbd_getTextFromCmd, id, 0)
      if ok and type(name) == "string" and want[key](name:lower()) then found = id; break end
    end
  end
  A.set("cmd_" .. key, found)
  CMD[key] = found > 0 and found or false
  return CMD[key] or nil
end

---------------------------------------------------------------- Enregistrement
-- se placer sur une réplique : sélection temporelle, curseur au pré-roll, piste de prises du personnage armée seule
function A.cue(line, preroll)
  local a, b = line.pos - 0.3, line.pos + line.len + 0.5
  reaper.GetSet_LoopTimeRange(true, false, math.max(0, a), b, false)
  reaper.SetEditCurPos(math.max(0, line.pos - preroll), true, false)
  local rec = A.rec_track(line.who)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local want = tr == rec and 1 or 0
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") ~= want and (want == 1 or track_name(tr):sub(1, #A.REC_PREFIX) == A.REC_PREFIX) then
      reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", want)
    end
  end
  A.set("cur", A.guid(line.item))
  A.build_bips(line)
  reaper.SetExtState(A.SEC, "stop_at", string.format("%.3f", b + 0.5), false)
  reaper.SetExtState(A.SEC, "loop_from", string.format("%.3f", math.max(0, line.pos - preroll)), false)
end

function A.current(lines)
  local g = A.get("cur", "")
  for i, l in ipairs(lines) do if A.guid(l.item) == g then return i end end
end

---------------------------------------------------------------- Réseau : adresse de cet ordinateur pour la tablette
function A.lan_ip()
  local cmds = P.WIN and { "ipconfig" } or { "ipconfig getifaddr en0", "ipconfig getifaddr en1", "hostname -I" }
  for _, c in ipairs(cmds) do
    local okp, h = pcall(io.popen, c .. (P.WIN and "" or " 2>/dev/null"))
    if okp and h then
      local out = h:read("a") or ""; h:close()
      for ip in out:gmatch("(%d+%.%d+%.%d+%.%d+)") do
        if not ip:match("^127%.") and not ip:match("^255") and not ip:match("%.255$") and not ip:match("^0%.") then return ip end
      end
    end
  end
end

return A
