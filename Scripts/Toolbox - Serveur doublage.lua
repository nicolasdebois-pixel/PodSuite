-- Toolbox - Serveur doublage.lua — à laisser tourner pendant la séance (lancé par la page Enregistrement).
--  • envoie les répliques à la bande rythmo (page doublage.html, sur cet ordinateur ou sur une tablette) ;
--  • garde le double bip calé sur la réplique en cours (même si on la déplace) et ne le rend audible qu'en enregistrement ;
--  • arrête la lecture ou l'enregistrement à la fin de la réplique, ou reboucle si « Boucle » est actif.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local A = dofile(dir .. "Toolbox_adr.lua")
local P = A.P
local SEC = A.SEC

local function enc(s)
  return (s:gsub("[%%|!\r\n]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function build(lines)
  local chars = A.characters()
  local lane = {}
  for i, c in ipairs(chars) do lane[c.name] = i - 1 end
  local out = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = table.concat({ string.format("%.4f", l.pos), string.format("%.4f", l.len), lane[l.who] or 0,
      enc(l.who), l.char.hex, enc(l.text), enc(l.vo or "") }, "|")
  end
  local lanes = {}
  for _, c in ipairs(chars) do lanes[#lanes + 1] = enc(c.name) .. "|" .. c.hex end
  return table.concat(out, "!"), table.concat(lanes, "!")
end

local last_state, last_proj, last_sig, counter, dirty_at = -1, nil, nil, 0, nil

---------------------------------------------------------------- Vidéo pour la tablette
-- La page affiche l'image elle-même : on copie le fichier vidéo du projet dans le dossier du serveur web de REAPER
-- (par morceaux, sans bloquer REAPER), puis on publie sa place sur la timeline.
local VID = { src = nil, size = 0, dest = nil, job = nil, pct = 0, stamp = "" }
local function find_video()
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local tk = reaper.GetActiveTake(it)
    if tk and reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
      local src = reaper.GetMediaItemTake_Source(tk)
      local parent = reaper.GetMediaSourceParent(src)
      if parent then src = parent end
      if reaper.GetMediaSourceType(src, "") == "VIDEO" then
        return it, tk, reaper.GetMediaSourceFileName(src, "")
      end
    end
  end
end
local function fsize(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local n = f:seek("end"); f:close(); return n
end
local function video_step()
  local it, tk, file = find_video()
  if not it or not file or file == "" then
    if VID.src then VID.src = nil end
    reaper.SetExtState(SEC, "video", "|||||none", false); return
  end
  local size = fsize(file) or 0
  if file ~= VID.src or size ~= VID.size then                -- nouvelle vidéo : on (re)copie
    if VID.job then VID.job.i:close(); VID.job.o:close() end
    local ext = (file:match("%.(%w+)$") or "mp4"):lower()
    VID.src, VID.size, VID.pct = file, size, 0
    VID.dest = "adr_video." .. ext
    local full = P.www_dir() .. P.SEP .. VID.dest
    if fsize(full) == size and reaper.GetExtState(SEC, "video_src") == file then
      VID.job = nil; VID.stamp = reaper.GetExtState(SEC, "video_stamp")
    else
      local i, o = io.open(file, "rb"), io.open(full .. ".part", "wb")
      if i and o then VID.job = { i = i, o = o, full = full, done = 0 } else VID.job = nil; reaper.SetExtState(SEC, "video", "|||||erreur", false); return end
    end
  end
  if VID.job then
    local J = VID.job
    for _ = 1, 8 do                                             -- 8 Mo par passage
      local chunk = J.i:read(1048576)
      if not chunk then
        J.i:close(); J.o:close()
        os.remove(J.full); os.rename(J.full .. ".part", J.full)
        VID.job = nil
        VID.stamp = tostring(os.time())
        reaper.SetExtState(SEC, "video_src", VID.src, true); reaper.SetExtState(SEC, "video_stamp", VID.stamp, true)
        break
      end
      J.o:write(chunk); J.done = J.done + #chunk
    end
    if VID.job then
      VID.pct = math.floor(J.done / math.max(1, VID.size) * 100)
      reaper.SetExtState(SEC, "video", string.format("||||%s|copie %d %%", "", VID.pct), false)
      return
    end
  end
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  local show = A.get("show_video", "1") == "1"
  reaper.SetExtState(SEC, "video", show and string.format("%s|%.4f|%.4f|%.4f|%s|ok", VID.dest, pos, offs, rate, VID.stamp) or "|||||off", false)
end
local next_video = 0
local session = tostring(os.time())
local was_playing = false

local function publish()
  local lines = A.lines()
  local cues, lanes = build(lines)
  counter = counter + 1
  reaper.SetExtState(SEC, "cues", cues, false)
  reaper.SetExtState(SEC, "lanes", lanes, false)
  reaper.SetExtState(SEC, "version", session .. "-" .. counter, false)
  local i = A.current(lines)
  local sig = i and string.format("%.3f", lines[i].pos) or ""
  if sig ~= last_sig then
    last_sig = sig
    reaper.PreventUIRefresh(1)
    A.build_bips(i and lines[i] or nil)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end
end

local function loop()
  if reaper.GetExtState(SEC, "stop_server") == "1" then reaper.DeleteExtState(SEC, "stop_server", false); return end
  local proj = reaper.EnumProjects(-1)
  local st = reaper.GetProjectStateChangeCount(proj)
  if st ~= last_state or proj ~= last_proj then
    last_state, last_proj = st, proj
    dirty_at = reaper.time_precise()
  end
  if dirty_at and reaper.time_precise() - dirty_at > 0.3 then  -- on attend la fin d'un geste avant de recalculer
    dirty_at = nil
    publish()
    last_state = reaper.GetProjectStateChangeCount(proj)
  end
  reaper.SetExtState(SEC, "rate", string.format("%.4f", reaper.Master_GetPlayRate(proj)), false)
  local now = reaper.time_precise()
  if VID.job or now >= next_video then next_video = now + 1; video_step() end
  reaper.SetExtState(SEC, "focus", A.get("focus", ""), false)
  reaper.SetExtState(SEC, "curpos", A.get("curpos", ""), false)

  -- bips audibles seulement en enregistrement (ou en lecture si demandé)
  local ps = reaper.GetPlayState()
  local recording, playing = ps & 4 == 4, ps & 1 == 1
  local bt = A.find_track(A.BIPS)
  if bt then
    local want = (recording or (playing and A.get("bips_play", "0") == "1")) and A.get("bips", "1") == "1"
    local mute = want and 0 or 1
    if reaper.GetMediaTrackInfo_Value(bt, "B_MUTE") ~= mute then reaper.SetMediaTrackInfo_Value(bt, "B_MUTE", mute) end
  end

  if not was_playing and playing then                        -- lecture lancée ailleurs que sur la réplique : pas d'arrêt auto
    local from = tonumber(reaper.GetExtState(SEC, "loop_from"))
    if not from or math.abs(reaper.GetPlayPosition() - from) > 0.5 then reaper.DeleteExtState(SEC, "stop_at", false) end
  end
  -- fin de réplique : arrêt, ou retour au pré-roll en boucle (pas pendant l'enregistrement)
  local stop_at = tonumber(reaper.GetExtState(SEC, "stop_at"))
  if playing and stop_at then
    local pos = reaper.GetPlayPosition()
    if pos >= stop_at then
      local from = tonumber(reaper.GetExtState(SEC, "loop_from"))
      if not recording and A.get("loop", "0") == "1" and from then
        reaper.SetEditCurPos(from, true, true)
      else
        reaper.OnStopButton()
        reaper.DeleteExtState(SEC, "stop_at", false)
        if recording then reaper.SetExtState(SEC, "just_recorded", "1", false) end
      end
    end
  end
  if was_playing and not playing then reaper.DeleteExtState(SEC, "stop_at", false) end
  was_playing = playing
  reaper.defer(loop)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.DeleteExtState(SEC, "stop_server", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
  reaper.DeleteExtState(SEC, "version", false)
  local bt = A.find_track(A.BIPS)
  if bt then reaper.SetMediaTrackInfo_Value(bt, "B_MUTE", 1) end
  if VID.job then VID.job.i:close(); VID.job.o:close(); os.remove(VID.job.full .. ".part") end
  reaper.DeleteExtState(SEC, "video", false)
  if reaper.GetExtState(SEC, "punch_on") == "1" then                -- on rend à REAPER son mode d'enregistrement normal
    local n = A.cmd("normal"); if n then reaper.Main_OnCommand(n, 0) end
    reaper.DeleteExtState(SEC, "punch_on", false)
  end
end)
P.install_page("doublage.html")
publish()
loop()
