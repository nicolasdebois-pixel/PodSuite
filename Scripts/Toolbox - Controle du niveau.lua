-- Toolbox - Controle du niveau.lua — fenêtre séparée du contrôle du niveau d'export.
-- La même chose est intégrée à la page « Export » de la fenêtre principale ; le moteur est dans Toolbox_loudness.lua.
local scriptdir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])") or ""
local L = dofile(scriptdir .. "Toolbox_loudness.lua")
local TITLE, NORMS, S, save, num, sgn, LRA_HIGH = L.TITLE, L.NORMS, L.S, L.save, L.num, L.sgn, L.LRA_HIGH
local UI, set_msg, verdict, suggestions = L.UI, L.set_msg, L.verdict, L.suggestions
local do_measure, do_correct, remove_lim, lim_gain = L.do_measure, L.do_correct, L.remove_lim, L.lim_gain

---------------------------------------------------------------- Interface
local W, H = 660, 760
local U = dofile(scriptdir .. "Toolbox_ui.lua")
U.init(TITLE, W, H)
local COL = {
  bg = { 0.10, 0.105, 0.12 }, panel = { 0.14, 0.15, 0.17 }, text = { 0.93, 0.93, 0.93 }, muted = { 0.6, 0.62, 0.67 },
  accent = { 0.97, 0.6, 0.22 }, line = { 0.24, 0.25, 0.28 }, ok = { 0.3, 0.8, 0.5 }, bad = { 0.95, 0.42, 0.32 },
}
local function col(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function fonts()
  gfx.setfont(1, "Arial", 15); gfx.setfont(2, "Arial", 13); gfx.setfont(3, "Arial", 19, string.byte("b"))
  gfx.setfont(4, "Arial", 13, string.byte("b")); gfx.setfont(5, "Arial", 26, string.byte("b"))
end
fonts()
local function text(s, x, y, c, f) gfx.setfont(f or 1); col(c or COL.text); gfx.x, gfx.y = x, y; gfx.drawstr(s) end
local function wrap(s, x, y, w, c, f)
  gfx.setfont(f or 2); col(c or COL.text)
  local line = ""
  local lh = gfx.texth + 3
  for word in s:gmatch("%S+") do
    local t = line == "" and word or (line .. " " .. word)
    if gfx.measurestr(t) > w and line ~= "" then
      gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh; line = word
    else line = t end
  end
  if line ~= "" then gfx.x, gfx.y = x, y; gfx.drawstr(line); y = y + lh end
  return y
end
local function hit(x, y, w, h) return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h end
local clicked, mouse_was = false, false
local function button(label, x, y, w, h, primary, active)
  local over = hit(x, y, w, h)
  if primary or active then col(COL.accent, over and 1 or 0.88) else col(COL.panel) end
  gfx.rect(x, y, w, h, 1)
  if not (primary or active) then col(COL.line); gfx.rect(x, y, w, h, 0) end
  gfx.setfont(4); local tw = gfx.measurestr(label)
  if primary or active then gfx.set(0.1, 0.06, 0.02) else col(COL.text) end
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - gfx.texth) / 2; gfx.drawstr(label)
  return clicked and over
end

local function tile(x, y, w, h, label, value, sub, ok)
  col(COL.panel); gfx.rect(x, y, w, h, 1)
  col(ok == nil and COL.line or (ok and COL.ok or COL.bad)); gfx.rect(x, y, 4, h, 1)
  text(label, x + 14, y + 10, COL.muted, 2)
  text(value, x + 14, y + 28, ok == nil and COL.text or (ok and COL.ok or COL.bad), 5)
  text(sub, x + 14, y + 62, COL.muted, 2)
end

local function draw()
  col(COL.bg); gfx.rect(0, 0, U.W(), U.H(), 1)
  local x, w = 24, W - 48
  text("Contrôle du niveau d'export", x, 18, COL.text, 3)
  text("Mesure le mix du master tel qu'il sera exporté, avant d'exporter.", x, 46, COL.muted, 2)
  local y = 80
  text("Norme visée", x, y + 6, COL.text, 1)
  local bw = 190
  for i, N in ipairs(NORMS) do
    local c, r = (i - 1) % 2, (i - 1) // 2
    if button(N.name, x + w - (2 - c) * (bw + 6) + 6, y + r * 34, bw, 28, false, S.norm == i) and not UI.busy then S.norm = i; save() end
  end
  local N = NORMS[S.norm]
  local rows = (#NORMS + 1) // 2
  local d = (N.tol % 1 ~= 0) and 1 or 0
  text(string.format("%s LUFS intégrés (± %s LU) · true peak max %s dBTP", num(N.target, 0), num(N.tol, d), num(N.tp, 0)), x + w - 2 * (bw + 6) + 6, y + rows * 34 + 2, COL.muted, 2)
  y = y + rows * 34 + 32
  if true then                                                   -- tout le projet, ou une partie seulement
    text("Portion mesurée", x, y + 6, COL.text, 1)
    if button("Tout le projet", x + w - 2 * (bw + 6) + 6, y, bw, 28, false, S.scope == "all") and not UI.busy then S.scope = "all"; save() end
    if button("Sélection temporelle", x + w - bw, y, bw, 28, false, S.scope == "sel") and not UI.busy then S.scope = "sel"; save() end
    y = y + 46
  else S.scope = "all" end
  if button(UI.busy and "Mesure…" or (UI.m and "Remesurer" or "Mesurer"), x, y, 200, 36, true) and not UI.busy then do_measure() end
  local g, en = lim_gain()
  if g then
    text(string.format("Toolbox limiter sur le master : gain %s dB%s", sgn(g), en and "" or " (désactivé)"), x + 214, y + 4, COL.muted, 2)
    if button("Retirer le limiteur", x + 214, y + 20, 150, 22) and not UI.busy then remove_lim() end
  end
  y = y + 52
  col(COL.line); gfx.line(x, y, x + w, y)
  y = y + 16
  local m = UI.m
  if not m then
    y = wrap("Cliquez sur « Mesurer ». REAPER lit tout le mix (plus vite que le temps réel) sans créer de fichier, puis l'outil compare le résultat à la norme choisie et propose quoi corriger.", x, y, w, COL.muted, 2)
  else
    local okL, okT = verdict(m, N)
    local tw = (w - 24) / 3
    tile(x, y, tw, 84, "Loudness intégrée", num(m.lufs) .. " LUFS", string.format("visé : %s à %s", num(N.target - N.tol, (N.tol % 1 ~= 0) and 1 or 0), num(N.target + N.tol, (N.tol % 1 ~= 0) and 1 or 0)), okL)
    tile(x + tw + 12, y, tw, 84, m.tp_src == "sample" and "Crête (échantillon)" or "True peak", sgn(m.tp) .. (m.tp_src == "sample" and " dBFS" or " dBTP"), m.tp_src == "sample" and ("max : " .. num(N.tp - 1, 0) .. " dBFS (marge)") or ("max : " .. num(N.tp, 0) .. " dBTP"), okT)
    tile(x + 2 * (tw + 12), y, tw, 84, "Écart de volume (LRA)", m.lra and (num(m.lra) .. " LU") or "—", "bas = voix régulière", m.lra and (m.lra <= LRA_HIGH) or nil)
    y = y + 100
    if okL and okT then text("✓  Prêt pour l'export", x, y, COL.ok, 3) else text("À corriger avant l'export", x, y, COL.bad, 3) end
    y = y + 34
    text("PISTES", x, y, COL.muted, 4)
    y = y + 20
    for _, s in ipairs(suggestions(m, N)) do
      col(COL.accent); gfx.rect(x + 2, y + 6, 5, 5, 1)
      y = wrap(s, x + 16, y, w - 16, COL.text, 2) + 4
    end
    if not (okL and okT) then
      y = y + 6
      if button("Corriger automatiquement", x, y, 230, 34, true) and not UI.busy then do_correct() end
      y = y + 44
    end
  end
  if UI.msg ~= "" then wrap(UI.msg, x, H - 34, w, COL.muted, 2) end
  gfx.update()
end

local function loop()
  local ch = gfx.getchar()
  U.frame()
  if ch < 0 or ch == 27 then save(); gfx.quit(); return end
  local cap = gfx.mouse_cap
  if ch == 32 then reaper.Main_OnCommand(40044, 0)
  elseif ch == 26 or (ch == 122 and cap & 4 == 4) then reaper.Main_OnCommand(cap & 8 == 8 and 40030 or 40029, 0)
  elseif ch == 25 or (ch == 121 and cap & 4 == 4) then reaper.Main_OnCommand(40030, 0) end
  local down = cap & 1 == 1
  clicked = down and not mouse_was
  mouse_was = down
  if UI.pending and UI.drawn then local f = UI.pending; UI.pending = nil; UI.drawn = false; f()
  elseif UI.pending then UI.drawn = true end            -- on affiche « Mesure en cours » avant de lancer la mesure
  draw()
  if PODSUITE_TEST then PODSUITE_TEST.UI, PODSUITE_TEST.correct, PODSUITE_TEST.sugg = UI, do_correct, suggestions end   -- tests automatiques
reaper.defer(loop)
end
if PODSUITE_TEST then PODSUITE_TEST.UI, PODSUITE_TEST.correct, PODSUITE_TEST.sugg = UI, do_correct, suggestions end   -- tests automatiques
reaper.defer(loop)
