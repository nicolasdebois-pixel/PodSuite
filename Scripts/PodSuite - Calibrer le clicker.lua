-- PodSuite - Calibrer le clicker.lua
-- Faites une sélection temporelle autour d'UN clic complet (appui + relâchement),
-- avec un peu de silence avant, sur la piste sélectionnée. Le script mémorise son empreinte.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")

local a, b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
local tr = reaper.GetSelectedTrack(0, 0)
if b - a < 0.1 or not tr then
  reaper.MB("Sélectionnez une piste, puis faites une sélection temporelle autour d'un clic\n(appui + relâchement, avec un peu de silence avant).", "PodSuite — Calibrer le clicker", 0)
  return
end
if b - a > 10 then b = a + 10 end

local r = P.track_reader(tr)
local s = r.read(a, math.floor((b - a) * P.SR))
r.close()

local tpl, gap = P.template_from(s)
if not tpl then
  reaper.MB("Calibration impossible : " .. gap .. ".", "PodSuite — Calibrer le clicker", 0)
  return
end
P.set("click_template", tpl)
P.set("click_gap", string.format("%.3f", gap))
reaper.MB(gap > 0
  and string.format("Clicker calibré.\nAppui et relâchement détectés, espacés de %d ms : ils compteront pour un seul clic.", math.floor(gap * 1000 + 0.5))
  or "Clicker calibré (un seul transitoire détecté).", "PodSuite — Calibrer le clicker", 0)
