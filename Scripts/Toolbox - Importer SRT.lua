-- Toolbox - Importer SRT.lua — importe un fichier de sous-titres .srt en répliques de doublage.
-- Une ligne « MARC: texte » va au personnage MARC ; les autres vont au personnage choisi dans la fenêtre.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local A = dofile(dir .. "Toolbox_adr.lua")
local P = A.P
local TITLE = "Podcast & ADR Toolbox — Importer un SRT"

local ok, path = reaper.GetUserFileNameForRead("", "Importer un fichier de sous-titres (.srt)", "*.srt")
if not ok then return end
local okIn, vals = reaper.GetUserInputs(TITLE, 2, "Décalage (secondes),Personnage par défaut,extrawidth=120", "0,VO")
if not okIn then return end
local offStr, defName = vals:match("^([^,]*),(.*)$")
local offset = tonumber((offStr or ""):gsub(",", ".")) or 0
if not defName or defName:match("^%s*$") then defName = "VO" end
defName = defName:match("^%s*(.-)%s*$")

local txt = P.read_file(path)
if not txt then P.notify("Impossible d'ouvrir le fichier.") return end
local subs = A.parse_srt(txt)
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local who = {}
for _, s in ipairs(subs) do
  local name = s.who or defName
  who[name] = true
  A.add_line(name, s.pos + offset, s.len, s.text)
end
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Toolbox : import SRT (" .. #subs .. " répliques)", -1)
local names = {}
for n in pairs(who) do names[#names + 1] = n end
table.sort(names)
P.notify(string.format("%d répliques importées%s.", #subs, #names > 0 and (" (personnages : " .. table.concat(names, ", ") .. ")") or ""))
