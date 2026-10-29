-- PodSuite - Reglages.lua — emplacement de Whisper, modèle, langue, vocabulaire, sensibilité des clics
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")
if P.settings_dialog() then
  reaper.MB("Réglages enregistrés. Whisper et le modèle sont trouvés.", "PodSuite", 0)
else
  reaper.MB("Réglages enregistrés, mais Whisper ou le modèle restent introuvables.\nRelancez ce script pour les indiquer.", "PodSuite", 0)
end
