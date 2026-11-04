-- Toolbox - Serveur doublage.lua — à laisser tourner pendant la séance (lancé par la page Enregistrement).
--  • envoie les répliques à la bande rythmo (page doublage.html, sur cet ordinateur ou sur une tablette) ;
--  • tient la piste « Bips » à jour (3 bips avant chaque réplique) et ne la rend audible qu'en enregistrement ;
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
local session = tostring(os.time())
local was_playing = false

local function publish()
  local lines = A.lines()
  local cues, lanes = build(lines)
  counter = counter + 1
  reaper.SetExtState(SEC, "cues", cues, false)
  reaper.SetExtState(SEC, "lanes", lanes, false)
  reaper.SetExtState(SEC, "version", session .. "-" .. counter, false)
  local sig = A.bip_signature(lines)
  if sig ~= last_sig then
    last_sig = sig
    reaper.PreventUIRefresh(1)
    A.build_bips(lines)
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
end)
P.install_page("doublage.html")
publish()
loop()
