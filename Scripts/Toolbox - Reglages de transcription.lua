-- Toolbox - Reglages de transcription.lua — emplacement de Whisper, modèle, langue, vocabulaire, sensibilité des clics
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "Toolbox_lib.lua")
if P.settings_dialog() then
  P.notify("Réglages enregistrés. Whisper et le modèle sont trouvés.")
else
  P.notify("Réglages enregistrés, mais Whisper ou le modèle restent introuvables.\nRelancez ce script pour les indiquer.")
end
