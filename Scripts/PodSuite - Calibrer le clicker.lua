-- PodSuite - Calibrer le clicker.lua
-- Apprend le son de VOTRE clicker, pour le reconnaître ensuite dans les enregistrements.
-- Le plus simple : placez le curseur d'édition juste avant un clic, sélectionnez la piste, lancez le script.
-- (Une sélection temporelle autour d'un clic fonctionne aussi.)
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")
local TITLE = "PodSuite — Calibrer le clicker"

local tr = reaper.GetSelectedTrack(0, 0)
if not tr and reaper.CountSelectedMediaItems(0) > 0 then tr = reaper.GetMediaItem_Track(reaper.GetSelectedMediaItem(0, 0)) end
if not tr then
  reaper.MB("Sélectionnez la piste qui contient le clic, placez le curseur juste avant le clic, puis relancez.", TITLE, 0)
  return
end

local a, b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if b - a < 0.1 then
  local cur = reaper.GetCursorPosition()
  a, b = math.max(0, cur - 0.1), cur + 1.5          -- on cherche le clic dans la seconde et demie qui suit le curseur
end
if b - a > 10 then b = a + 10 end

local r = P.track_reader(tr)
local s = r.read(a, math.floor((b - a) * P.SR))
r.close()

local tpl, gap, peak = P.template_from(s)
if not tpl then
  reaper.MB("Je ne trouve pas de clic net juste après le curseur (" .. gap .. ").\n\nPlacez le curseur un tout petit peu AVANT le clic (moins d'une seconde avant), sur la piste du micro, puis relancez.", TITLE, 0)
  return
end
local t = a + (peak - 1) / P.SR
reaper.SetEditCurPos(t, true, false)                  -- montre le clic trouvé
local mm, ss = math.floor(t / 60), t % 60
if reaper.MB(string.format("Clic trouvé à %d:%05.2f (le curseur y est placé).%s\n\nMémoriser ce son comme celui de votre clicker ?",
    mm, ss, gap > 0 and string.format("\nAppui et relâchement détectés, espacés de %d ms : ils compteront pour un seul clic.", math.floor(gap * 1000 + 0.5)) or ""),
    TITLE, 4) ~= 6 then return end
P.set("click_template", tpl)
P.set("click_gap", string.format("%.3f", gap))
reaper.MB("Clicker calibré.\n\nRelancez « PodSuite - Transcrire » : les clics seront détectés et apparaîtront dans la page de dérushage.", TITLE, 0)
