-- Ripple edge (Podcast & ADR Toolbox) — tourne en arrière-plan, activé depuis la page « Montage ».
-- Pendant qu'on tire le bord d'un item, ses voisins suivent EN DIRECT, du même décalage :
--   • bord droit  : tout ce qui suit l'item se décale ;
--   • bord gauche : tout ce qui précède l'item se décale.
-- Portée : la piste de l'item, ou toutes les pistes si le ripple « toutes les pistes » de REAPER est actif.
-- Aucun fondu n'est ajouté : les items ne se chevauchent jamais, et les fondus d'origine sont rétablis au relâchement.
-- Un geste à la souris ne change pas le « compteur d'état » du projet tant que le bouton est enfoncé : c'est ce qui
-- distingue un bord qu'on tire (on suit en direct) d'une action, d'une annulation ou d'un rétablissement (on ne touche à rien).

local SECTION = "PODSUITE"
local EPS = 0.0005

local function ripple_all_tracks()
  local id = tonumber(reaper.GetExtState(SECTION, "ripple_cmd_all"))
  return id and reaper.GetToggleCommandState(id) == 1
end
local function near(a, b) return math.abs(a - b) < EPS end

local function read_all()
  local t, n = {}, reaper.CountMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetMediaItem(0, i)
    local tk = reaper.GetActiveTake(it)
    t[it] = {
      track = reaper.GetMediaItem_Track(it),
      pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
      len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
      offs = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0,
      rate = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1,
    }
  end
  return t, n
end

local FADES = { "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO" }
local function read_fades(items)
  local f = {}
  for it in pairs(items) do
    local v = {}
    for k, key in ipairs(FADES) do v[k] = reaper.GetMediaItemInfo_Value(it, key) end
    f[it] = v
  end
  return f
end
local function restore_fades(saved)
  for it, v in pairs(saved) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      for k, key in ipairs(FADES) do
        if not near(reaper.GetMediaItemInfo_Value(it, key), v[k]) then reaper.SetMediaItemInfo_Value(it, key, v[k]) end
      end
    end
  end
end

-- bords modifiés depuis l'image précédente
local function edge_changes(prev, cur)
  local trims, moved = {}, {}
  for it, n in pairs(cur) do
    local o = prev[it]
    if o and o.track == n.track and near(o.rate, n.rate) then
      local d = n.pos - o.pos
      if not near(d, 0) and near(o.pos + o.len, n.pos + n.len) and near(n.offs - o.offs, d * n.rate) then
        trims[#trims + 1] = { item = it, side = "L", d = d, o = o }
      elseif near(d, 0) and not near(o.len, n.len) and near(o.offs, n.offs) then
        trims[#trims + 1] = { item = it, side = "R", d = n.len - o.len, o = o }
      elseif not near(d, 0) and near(o.len, n.len) then
        moved[it] = d                                         -- déplacé par REAPER (son propre ripple)
      end
    end
  end
  return trims, moved
end

-- décale les voisins ; renvoie true si quelque chose a bougé
local function follow(trims, moved, prev)
  local all = ripple_all_tracks()
  local is_trim, shift = {}, {}
  for _, t in ipairs(trims) do is_trim[t.item] = true end
  for _, t in ipairs(trims) do
    local o = t.o
    local done = false                                        -- REAPER a-t-il déjà décalé les voisins ?
    for it, d in pairs(moved) do
      local e = prev[it]
      if (all or e.track == o.track) and near(d, t.d) then done = true end
    end
    if not done then
      for it, e in pairs(prev) do
        if not is_trim[it] and (all or e.track == o.track) then
          if t.side == "R" and e.pos >= o.pos + o.len - EPS then shift[it] = (shift[it] or 0) + t.d end
          if t.side == "L" and e.pos + e.len <= o.pos + EPS then shift[it] = (shift[it] or 0) + t.d end
        end
      end
    end
  end
  local any = false
  for it, v in pairs(shift) do
    if not near(v, 0) then
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, prev[it].pos + v)); any = true
    end
  end
  return any
end

---------------------------------------------------------------- Boucle
local prev, pcount = read_all()
local last_state = reaper.GetProjectStateChangeCount(0)
local proj = reaper.EnumProjects(-1)
local drag = nil                                              -- { fades = ... } pendant un geste

local function loop()
  if reaper.GetExtState(SECTION, "ripple_stop") == "1" then reaper.DeleteExtState(SECTION, "ripple_stop", false); return end
  local p = reaper.EnumProjects(-1)
  local state = reaper.GetProjectStateChangeCount(0)
  local cur, count = read_all()
  if p ~= proj or count ~= pcount then
    proj, drag = p, nil
  else
    local state_changed = state ~= last_state
    if not state_changed or drag then                        -- geste en cours (ou sa toute dernière image)
      local trims, moved = edge_changes(prev, cur)
      if #trims > 0 then
        if not drag then drag = { fades = read_fades(prev) } end
        reaper.PreventUIRefresh(1)
        local moved_any = follow(trims, moved, cur)
        reaper.PreventUIRefresh(-1)
        if moved_any then reaper.UpdateArrange(); cur = read_all() end
      end
    end
    if state_changed and drag then                           -- bouton relâché : pas de fondus ajoutés
      restore_fades(drag.fades)
      reaper.UpdateArrange()
      drag = nil
      cur = read_all()
    end
  end
  last_state = reaper.GetProjectStateChangeCount(0)
  prev, pcount = cur, count
  reaper.defer(loop)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.DeleteExtState(SECTION, "ripple_stop", false)
reaper.SetToggleCommandState(sec, cmd, 1); reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(function() reaper.SetToggleCommandState(sec, cmd, 0); reaper.RefreshToolbar2(sec, cmd) end)
loop()
