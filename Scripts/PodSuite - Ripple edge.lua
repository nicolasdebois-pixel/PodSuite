-- PodSuite - Ripple edge.lua
-- Tourne en arrière-plan (à activer depuis la fenêtre PodSuite, page « Montage »).
-- Quand on raccourcit ou rallonge un item par un de ses bords, ce qui l'entoure suit :
--   • bord droit  : tout ce qui suit l'item se décale d'autant (le trou se referme ou la place se fait) ;
--   • bord gauche : au choix, l'item et ce qui le suit reculent (réglage par défaut), ou ce qui le précède avance.
-- Portée : la piste de l'item, ou toutes les pistes si le ripple « toutes les pistes » de REAPER est actif.
-- Le calcul se fait une fois le geste terminé (au relâchement de la souris) ; Ctrl/Cmd+Z annule le décalage.

local SECTION = "PODSUITE"
local EPS = 0.0005

local function ripple_all_tracks()
  local id = tonumber(reaper.GetExtState(SECTION, "ripple_cmd_all"))
  return id and reaper.GetToggleCommandState(id) == 1
end
local function left_mode() return reaper.GetExtState(SECTION, "ripple_left") == "before" and "before" or "after" end

---------------------------------------------------------------- Photo des items
local function snapshot()
  local snap, list = {}, {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local tk = reaper.GetActiveTake(it)
    local e = {
      item = it, track = reaper.GetMediaItem_Track(it),
      pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
      len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
      offs = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0,
      rate = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1,
    }
    local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    snap[guid] = e; list[#list + 1] = guid
  end
  return snap, list
end

local function near(a, b) return math.abs(a - b) < EPS end

---------------------------------------------------------------- Analyse d'un geste terminé
-- Renvoie la liste des bords modifiés : { guid, side = "L"/"R", d = décalage (+ = vers la droite), old = ancien e }
local function find_trims(old, new)
  local trims, others = {}, {}
  for g, n in pairs(new) do
    local o = old[g]
    if o and (not near(o.pos, n.pos) or not near(o.len, n.len) or not near(o.offs, n.offs)) then
      if o.track == n.track and near(o.rate, n.rate) then
        local d = n.pos - o.pos
        if not near(d, 0) and near(o.pos + o.len, n.pos + n.len) and near(n.offs - o.offs, d * n.rate) then
          trims[#trims + 1] = { guid = g, side = "L", d = d, old = o }
        elseif near(d, 0) and not near(o.len, n.len) and near(o.offs, n.offs) then
          trims[#trims + 1] = { guid = g, side = "R", d = n.len - o.len, old = o }
        else others[#others + 1] = { guid = g, d = d, o = o, n = n }
        end
      else others[#others + 1] = { guid = g, d = n.pos - o.pos, o = o, n = n } end
    end
  end
  return trims, others
end

local function concerned(e, track, all) return all or e.track == track end

local function apply(trims, others, old, new)
  local all = ripple_all_tracks()
  local lmode = left_mode()
  local shift = {}                                  -- guid -> décalage à appliquer
  local function add(g, v) shift[g] = (shift[g] or 0) + v end
  local is_trim = {}
  for _, t in ipairs(trims) do is_trim[t.guid] = true end
  -- les autres changements doivent être de simples déplacements (ceux du ripple de REAPER), sinon on ne touche à rien
  for _, o in ipairs(others) do
    if not (near(o.o.len, o.n.len) and near(o.o.offs, o.n.offs)) then return false end
  end
  for _, t in ipairs(trims) do
    local o = t.old
    local old_end = o.pos + o.len
    if t.side == "R" then
      -- REAPER a-t-il déjà décalé ce qui suit (ripple natif) ? alors on ne fait rien
      local done = false
      for _, x in ipairs(others) do
        if x.o.pos >= old_end - EPS and near(x.d, t.d) and concerned(x.o, o.track, all) then done = true end
      end
      if not done then
        for g, e in pairs(old) do
          if not is_trim[g] and new[g] and e.pos >= old_end - EPS and concerned(e, o.track, all) then add(g, t.d) end
        end
      end
    else
      if lmode == "after" then
        add(t.guid, -t.d)                            -- l'item revient à sa place de départ…
        for g, e in pairs(old) do                   -- …et tout ce qui le suit recule avec lui
          if g ~= t.guid and new[g] and e.pos >= old_end - EPS and concerned(e, o.track, all) then add(g, -t.d) end
        end
      else
        for g, e in pairs(old) do                   -- ce qui précède avance pour rejoindre le nouveau début
          if g ~= t.guid and new[g] and e.pos + e.len <= o.pos + EPS and concerned(e, o.track, all) then add(g, t.d) end
        end
      end
    end
  end
  local any = false
  for _, v in pairs(shift) do if not near(v, 0) then any = true end end
  if not any then return false end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for g, v in pairs(shift) do
    if not near(v, 0) then
      local it = new[g].item
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, reaper.GetMediaItemInfo_Value(it, "D_POSITION") + v))
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("PodSuite : ripple edge", 4)
  return true
end

---------------------------------------------------------------- Boucle
local snap = snapshot()
local last = reaper.GetProjectStateChangeCount(0)
local proj = reaper.EnumProjects(-1)

local function loop()
  if reaper.GetExtState(SECTION, "ripple_stop") == "1" then reaper.DeleteExtState(SECTION, "ripple_stop", false); return end
  local p = reaper.EnumProjects(-1)
  local c = reaper.GetProjectStateChangeCount(0)
  if p ~= proj then proj = p; snap = snapshot(); last = c
  elseif c ~= last then
    last = c
    local new = snapshot()
    local undo = reaper.Undo_CanUndo2(0) or ""
    local redo = reaper.Undo_CanRedo2(0) or ""
    -- on ignore nos propres décalages, et les annulations / rétablissements (pile « rétablir » non vide)
    if not undo:find("PodSuite : ripple edge", 1, true) and redo == "" then
      local trims, others = find_trims(snap, new)
      if #trims > 0 and apply(trims, others, snap, new) then
        new = snapshot(); last = reaper.GetProjectStateChangeCount(0)
      end
    end
    snap = new
  end
  reaper.defer(loop)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.DeleteExtState(SECTION, "ripple_stop", false)
reaper.SetExtState(SECTION, "ripple_running", "1", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function()
  reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd)
  reaper.DeleteExtState(SECTION, "ripple_running", false)
end)
loop()
