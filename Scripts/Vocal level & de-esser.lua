-- Vocal level & de-esser — fenêtre complète (réglages avancés). La version simple est dans la page « Voix »
-- de la fenêtre principale. Le moteur (analyse, courbes) est dans Toolbox_vocal.lua.
local scriptdir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local V = dofile(scriptdir .. "Toolbox_vocal.lua")
local TITLE, S, DEF, PRESETS, LEVELS, save = V.TITLE, V.S, V.DEF, V.PRESETS, V.LEVELS, V.save
local ST, cache, take_key, selected_takes, find_fx = V.ST, V.cache, V.take_key, V.selected_takes, V.find_fx
local apply_all, start_analysis, retouch, zone_state, fx_state, toggle_bypass, remove_all =
  V.apply_all, V.start_analysis, V.retouch, V.zone_state, V.fx_state, V.toggle_bypass, V.remove_all
local RET, RET_ORDER, BANDS, eq_response, set_msg = V.RET, V.RET_ORDER, V.BANDS, V.eq_response, V.set_msg
local SEP = package.config:sub(1, 1)

---------------------------------------------------------------- Interface
local AW, AH, SW, SH = 940, 750, 680, 720
local EXPERT = reaper.GetExtState("PODSUITE", "expert") == "1"   -- mode Simple de la boîte à outils : pas de réglages avancés
if not EXPERT then S.adv = 0 end
local W, H = AW, AH
if S.adv ~= 1 then W, H = SW, SH end
local U = dofile(scriptdir .. "Toolbox_ui.lua")
U.init(TITLE, W, H)
local UI = V.UI
UI.drag, UI.mouse_was = nil, false

local COL = {
  bg = { 0.10, 0.105, 0.12 }, panel = { 0.14, 0.15, 0.17 }, text = { 0.93, 0.93, 0.93 }, muted = { 0.6, 0.62, 0.67 },
  accent = { 0.97, 0.6, 0.22 }, line = { 0.24, 0.25, 0.28 }, ok = { 0.3, 0.8, 0.5 },
}
local function col(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function text(s, x, y, c, f) gfx.setfont(f or 1); col(c or COL.text); gfx.x, gfx.y = x, y; gfx.drawstr(s) end
gfx.setfont(1, "Arial", 15); gfx.setfont(2, "Arial", 13); gfx.setfont(3, "Arial", 19, string.byte("b")); gfx.setfont(4, "Arial", 13, string.byte("b"))

local function hit(x, y, w, h) return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h end

local clicked = false
local function button(label, x, y, w, h, primary, active)
  local over = hit(x, y, w, h)
  if primary or active then col(COL.accent, over and 1 or 0.88) else col(COL.panel); end
  gfx.rect(x, y, w, h, 1)
  col(COL.line); if not (primary or active) then gfx.rect(x, y, w, h, 0) end
  gfx.setfont(4); local tw = gfx.measurestr(label)
  if primary or active then gfx.set(0.1, 0.06, 0.02) else col(COL.text) end
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - gfx.texth) / 2; gfx.drawstr(label)
  return clicked and over
end

-- curseur : renvoie true quand l'utilisateur relâche après l'avoir bougé
local function slider(id, label, key, mn, mx, step, fmt, x, y, w, disabled)
  text(label, x, y, disabled and COL.muted or COL.text, 2)
  local v = S[key]
  local vs = fmt(v)
  gfx.setfont(2); local tw = gfx.measurestr(vs)
  text(vs, x + w - tw, y, disabled and COL.muted or COL.accent, 2)
  local ty = y + 20
  col(COL.line); gfx.rect(x, ty, w, 4, 1)
  local f = (v - mn) / (mx - mn)
  if not disabled then col(COL.accent); gfx.rect(x, ty, math.floor(w * f), 4, 1) end
  col(disabled and COL.muted or COL.text); gfx.circle(x + w * f, ty + 2, 6, 1, 1)
  local released = false
  if not disabled then
    if gfx.mouse_cap & 1 == 1 then
      if UI.drag == nil and clicked and hit(x - 6, ty - 8, w + 12, 20) then UI.drag = id end
      if UI.drag == id then
        local nf = math.max(0, math.min(1, (gfx.mouse_x - x) / w))
        local nv = mn + nf * (mx - mn)
        nv = math.floor(nv / step + 0.5) * step
        S[key] = nv
      end
    elseif UI.drag == id then UI.drag = nil; released = true end
  end
  return released
end

local function fmt_db(v) return (v > 0 and "+" or (v < 0 and "−" or "")) .. string.format("%g dB", math.abs(v)) end

-- section « Retouche locale » ; renvoie sa hauteur
local function draw_retouch(x, y, w)
  col(COL.line); gfx.line(x, y, x + w, y)
  text("RETOUCHE LOCALE", x, y + 10, COL.muted, 4)
  local st, n, s, t = zone_state()
  if not st then
    text("Sélection temporelle sur le son à retoucher (ex. le « B » de « Bonjour »), puis un réglage ci-dessous.", x, y + 30, COL.muted, 2)
  else
    gfx.setfont(4); local hx = x + gfx.measurestr("RETOUCHE LOCALE") + 14
    text(string.format("zone %.2f → %.2f s (%d ms)%s", s, t, math.floor((t - s) * 1000 + 0.5),
      n > 0 and string.format(" · %d retouche%s ici", n, n > 1 and "s" or "") or ""), hx, y + 11, COL.accent, 2)
    if n > 0 and button("Effacer la zone", x + w - 130, y + 6, 130, 22) then retouch(nil) end
    text("Seule cette zone change : le reste du traitement n'est pas modifié.", x, y + 30, COL.muted, 2)
  end
  local ry = y + 52
  for _, k in ipairs(RET_ORDER) do
    local R = RET[k]
    text(R.name, x, ry + 5, st and COL.text or COL.muted, 4)
    text(R.desc, x + 86, ry + 6, COL.muted, 2)
    local bw = 66
    local bx = x + w - 4 * (bw + 4) + 4
    for i, v in ipairs(R.steps) do
      local shown = (k == "lvl") and v or -v
      if button(fmt_db(shown), bx + (i - 1) * (bw + 4), ry, bw, 24, false, st and st[k] == v) and st then retouch(k, v) end
    end
    ry = ry + 30
  end
  return ry - y + 4
end

-- bouton principal : « Analyser et appliquer » tant que la sélection n'est pas traitée, puis « Bypass »
local function main_button(x, y, w, h)
  if ST.job and ST.cancel_job then
    if button("Annuler l'analyse", x, y, w, h, false) then ST.cancel_job() end
    return
  end
  local done, byp = fx_state()
  if done then
    if button(byp and "Bypass (son d'origine)" or "Bypass", x, y, w, h, false, byp) then toggle_bypass() end
  elseif button("Analyser et appliquer", x, y, w, h, true) then start_analysis() end
end

-- guide d'utilisation (page HTML installée à côté du script)
local GUIDE = "Vocal level - Guide.html"
local function open_guide()
  local dir = scriptpath and scriptpath:match("^(.*)[/\\]") or ""
  local path = dir .. SEP .. GUIDE
  local f = io.open(path, "rb")
  if not f then set_msg("Guide introuvable : synchronisez les paquets dans ReaPack."); return end
  f:close()
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(path); return end
  local os_name = reaper.GetOS()
  if os_name:match("^Win") then os.execute('start "" "' .. path .. '"')
  elseif os_name:match("^OSX") or os_name:match("^mac") then os.execute('open "' .. path .. '"')
  else os.execute('xdg-open "' .. path .. '"') end
end

local function eq_graph(x, y, w, h)
  col(COL.panel); gfx.rect(x, y, w, h, 1)
  local fmin, fmax, dbr = 80, 14000, 12
  local function fx(f) return x + w * math.log(f / fmin) / math.log(fmax / fmin) end
  local function fy(v) return y + h / 2 - v / dbr * (h / 2 - 6) end
  col(COL.line)
  for _, f in ipairs({ 100, 1000, 10000 }) do gfx.line(fx(f), y, fx(f), y + h) end
  gfx.line(x, fy(0), x + w, fy(0))
  gfx.setfont(2)
  for _, f in ipairs({ { 100, "100" }, { 1000, "1k" }, { 10000, "10k" } }) do col(COL.muted); gfx.x, gfx.y = fx(f[1]) + 3, y + h - 14; gfx.drawstr(f[2]) end
  local r = UI.eq
  if not r or S.eq_on ~= 1 then
    col(COL.muted); gfx.x, gfx.y = x + 10, y + 8; gfx.drawstr(S.eq_on == 1 and "La courbe apparaît après l'analyse." or "Égalisation désactivée.")
    return
  end
  -- écart mesuré (gris) et correction appliquée (orange)
  local px, py
  col(COL.muted, 0.8)
  for k, f in ipairs(BANDS) do
    local v = math.max(-dbr, math.min(dbr, r.m[k] - r.t[k]))
    local X, Y = fx(f), fy(v)
    if px then gfx.line(px, py, X, Y, 1) end
    px, py = X, Y
  end
  px = nil
  col(COL.accent)
  for i = 0, 120 do
    local f = fmin * (fmax / fmin) ^ (i / 120)
    local X, Y = fx(f), fy(math.max(-dbr, math.min(dbr, eq_response(r.gains, f))))
    if px then gfx.line(px, py, X, Y, 1); gfx.line(px, py + 1, X, Y + 1, 1) end
    px, py = X, Y
  end
  gfx.setfont(2); col(COL.muted); gfx.x, gfx.y = x + 8, y + 6; gfx.drawstr("gris : écart de la voix à la référence")
  col(COL.accent); gfx.x, gfx.y = x + 8, y + 20; gfx.drawstr("orange : correction appliquée")
end

local function resize_to(adv)
  S.adv = adv
  W, H = adv == 1 and AW or SW, adv == 1 and AH or SH
  gfx.quit(); U.init(TITLE, W, H)
  gfx.setfont(1, "Arial", 15); gfx.setfont(2, "Arial", 13); gfx.setfont(3, "Arial", 19, string.byte("b")); gfx.setfont(4, "Arial", 13, string.byte("b"))
  UI.skip_click = true
end

-- Vue simple : un choix Parole / Chant, quatre traitements avec une intensité chacun, un bouton
local ROWS = {
  { key = "rider_on", lv = "lv_rider", set = "rider", name = "Niveau régulier", desc = "Remonte les passages faibles, baisse les trop forts" },
  { key = "de_on", lv = "lv_de", set = "de", name = "Sifflantes", desc = "Adoucit les « s », « ch » et « z » qui sifflent" },
  { key = "plo_on", lv = "lv_plo", set = "plo", name = "Plosives", desc = "« p » et « b » qui soufflent dans le micro (bouffées de grave)" },
  { key = "prox_on", lv = "lv_prox", set = "prox", name = "Voix trop proche", desc = "Graves qui gonflent quand on s'approche du micro" },
  { key = "eq_on", lv = "lv_eq", set = "eq", name = "Équilibre de la voix", desc = "Voix trop sourde, trop nasale ou trop brillante" },
}
local function draw_simple()
  col(COL.bg); gfx.rect(0, 0, U.W(), U.H(), 1)
  text(TITLE, 24, 18, COL.text, 3)
  local n = #ST.takes
  local analysed = 0
  for _, e in ipairs(ST.takes) do if cache[take_key(e.item, e.take)] then analysed = analysed + 1 end end
  text(n == 0 and "Sélectionnez un ou plusieurs items de voix" or string.format("%d item%s sélectionné%s · %s", n, n > 1 and "s" or "", n > 1 and "s" or "", analysed == n and "analysé" .. (n > 1 and "s" or "") or "pas encore analysé"), 24, 46, COL.muted, 2)
  local chg = false
  local x, w = 24, W - 48
  local y = 82
  text("Type de voix", x, y + 5, COL.text, 1)
  if button("Parole", x + w - 210, y, 100, 28, false, S.mode == "parole") then S.mode = "parole"; for k, v in pairs(PRESETS.parole) do S[k] = v end; chg = true end
  if button("Chant", x + w - 104, y, 104, 28, false, S.mode == "chant") then S.mode = "chant"; for k, v in pairs(PRESETS.chant) do S[k] = v end; chg = true end
  y = y + 46
  for _, r in ipairs(ROWS) do
    col(COL.line); gfx.line(x, y, x + w, y)
    local on = S[r.key] == 1
    -- case à cocher
    local cx, cy = x, y + 18
    col(on and COL.accent or COL.panel); gfx.rect(cx, cy, 20, 20, 1)
    col(COL.line); if not on then gfx.rect(cx, cy, 20, 20, 0) end
    if on then gfx.set(0.1, 0.06, 0.02); gfx.line(cx + 4, cy + 10, cx + 8, cy + 15); gfx.line(cx + 8, cy + 15, cx + 16, cy + 5) end
    if clicked and hit(cx - 4, cy - 4, 260, 46) then S[r.key] = on and 0 or 1; chg = true; on = not on end
    text(r.name, x + 32, y + 14, on and COL.text or COL.muted, 4)
    text(r.desc, x + 32, y + 33, COL.muted, 2)
    local bx = x + w - 3 * 68
    for i, lab in ipairs({ "Léger", "Moyen", "Fort" }) do
      if button(lab, bx + (i - 1) * 68, y + 16, 64, 26, false, on and S[r.lv] == i) and on then
        S[r.lv] = i
        for k, v in pairs(LEVELS[r.set][i]) do S[k] = v end
        chg = true
      end
    end
    y = y + 60
  end
  y = y + 6
  y = y + draw_retouch(x, y, w)
  col(COL.line); gfx.line(x, y, x + w, y)
  y = y + 10
  if UI.progress then col(COL.line); gfx.rect(x, y, w, 6, 1); col(COL.accent); gfx.rect(x, y, math.floor(w * UI.progress), 6, 1) end
  if UI.stats then text(UI.stats, x, y + 12, COL.ok, 2) end
  text(UI.msg, x, y + 30, COL.muted, 2)
  local by = H - 54
  main_button(x, by, 220, 36)
  if button("Guide d'utilisation", x + 230, by, 170, 36) then open_guide() end
  if EXPERT and button("Réglages avancés", x + w - 160, by, 160, 36) then resize_to(1); return true end
  if chg and not ST.job then
    local any = false
    for _, e in ipairs(ST.takes) do if cache[take_key(e.item, e.take)] then any = true end end
    if any then apply_all() else save() end
  end
  gfx.update()
  return true
end

local function draw()
  if S.adv ~= 1 then return draw_simple() end
  col(COL.bg); gfx.rect(0, 0, U.W(), U.H(), 1)
  text(TITLE, 22, 16, COL.text, 3)
  local n = #ST.takes
  local analysed = 0
  for _, e in ipairs(ST.takes) do if cache[take_key(e.item, e.take)] then analysed = analysed + 1 end end
  text(n == 0 and "Aucun item sélectionné" or string.format("%d item%s · %s", n, n > 1 and "s" or "", analysed == n and "analysé" .. (n > 1 and "s" or "") or "à analyser"), 22, 42, COL.muted, 2)
  if button(S.rider_on == 1 and "Rider activé" or "Rider désactivé", W - 330, 16, 126, 26, false, S.rider_on == 1) then S.rider_on = 1 - S.rider_on; UI.chg = true end
  if button("Parole", W - 196, 16, 84, 26, false, S.mode == "parole") then S.mode = "parole"; for k, v in pairs(PRESETS.parole) do S[k] = v end; UI.chg = true end
  if button("Chant", W - 106, 16, 84, 26, false, S.mode == "chant") then S.mode = "chant"; for k, v in pairs(PRESETS.chant) do S[k] = v end; UI.chg = true end

  local chg, reanalyse = UI.chg or false, false
  UI.chg = false
  local gap = 36
  local cw = (W - 44 - gap) / 2
  -------- colonne gauche
  local x, w, y = 22, cw, 70
  col(COL.line); gfx.line(x, y, x + w, y)
  text("RIDER — niveau régulier", x, y + 10, COL.muted, 4)
  y = y + 38
  if button(S.auto == 1 and "Cible : automatique" or "Cible : fixe", x, y, 150, 24, false, false) then S.auto = 1 - S.auto; chg = true end
  chg = slider("target", "Niveau cible", "target", -40, -8, 0.5, function(v) return string.format("%.1f dB", v) end, x + 166, y - 2, w - 166, S.auto == 1) or chg
  y = y + 46
  chg = slider("amount", "Quantité", "amount", 0, 100, 1, function(v) return string.format("%d %%", v) end, x, y, w) or chg
  y = y + 44
  chg = slider("range", "Correction maximale", "range", 1, 15, 0.5, function(v) return string.format("± %.1f dB", v) end, x, y, w) or chg
  y = y + 44
  chg = slider("release", "Retour après une réduction (relâchement)", "release", 300, 4000, 50, function(v) return string.format("%.2f s", v / 1000) end, x, y, w) or chg
  y = y + 52
  col(COL.line); gfx.line(x, y, x + w, y)
  text("DE-ESSER — sifflantes", x, y + 10, COL.muted, 4)
  if button(S.de_on == 1 and "Activé" or "Désactivé", x + w - 100, y + 6, 100, 24, false, S.de_on == 1) then S.de_on = 1 - S.de_on; chg = true end
  y = y + 40
  local off = S.de_on ~= 1
  chg = slider("depth", "Atténuation maximale", "depth", 0, 15, 0.5, function(v) return string.format("%.1f dB", v) end, x, y, w, off) or chg
  y = y + 44
  chg = slider("sens", "Sensibilité", "sens", 0, 100, 1, function(v) return string.format("%d", v) end, x, y, w, off) or chg
  y = y + 44
  reanalyse = slider("freq", "Fréquence", "freq", 3000, 10000, 100, function(v) return string.format("%.1f kHz", v / 1000) end, x, y, w, off) or reanalyse
  y = y + 42
  if button("Aigus seulement", x, y, 150, 24, false, S.split == 1) then S.split = 1; chg = true end
  if button("Tout le signal", x + 156, y, 130, 24, false, S.split == 0) then S.split = 0; chg = true end

  -------- colonne droite
  x, y = 22 + cw + gap, 70
  col(COL.line); gfx.line(x, y, x + w, y)
  text("GRAVES", x, y + 10, COL.muted, 4)
  if button("Plosives", x + w - 206, y + 6, 100, 24, false, S.plo_on == 1) then S.plo_on = 1 - S.plo_on; chg = true end
  if button("Proximité", x + w - 100, y + 6, 100, 24, false, S.prox_on == 1) then S.prox_on = 1 - S.prox_on; chg = true end
  y = y + 40
  local offp, offx = S.plo_on ~= 1, S.prox_on ~= 1
  local hw2 = (w - 20) / 2
  chg = slider("plo_depth", "Plosives : atténuation", "plo_depth", 0, 30, 1, function(v) return string.format("%d dB", v) end, x, y, hw2, offp) or chg
  chg = slider("plo_sens", "Plosives : sensibilité", "plo_sens", 0, 100, 1, function(v) return string.format("%d", v) end, x + hw2 + 20, y, hw2, offp) or chg
  y = y + 44
  chg = slider("lo_depth", "Proximité : atténuation", "lo_depth", 0, 18, 0.5, function(v) return string.format("%.1f dB", v) end, x, y, hw2, offx) or chg
  chg = slider("prox", "Proximité : quantité", "prox", 0, 100, 1, function(v) return string.format("%d %%", v) end, x + hw2 + 20, y, hw2, offx) or chg
  y = y + 44
  reanalyse = slider("lowfreq", "Proximité : fréquence", "lowfreq", 60, 400, 5, function(v) return string.format("%d Hz", v) end, x, y, hw2, offx) or reanalyse
  chg = slider("hpf", "Coupe-bas (0 = aucun)", "hpf", 0, 150, 5, function(v) return v == 0 and "aucun" or string.format("%d Hz", v) end, x + hw2 + 20, y, hw2, offp) or chg
  y = y + 52
  col(COL.line); gfx.line(x, y, x + w, y)
  text("ÉGALISATION — correction tonale", x, y + 10, COL.muted, 4)
  if button(S.eq_on == 1 and "Activée" or "Désactivée", x + w - 100, y + 6, 100, 24, false, S.eq_on == 1) then S.eq_on = 1 - S.eq_on; chg = true end
  y = y + 40
  off = S.eq_on ~= 1
  local hw = (w - 20) / 2
  chg = slider("eq_amount", "Quantité", "eq_amount", 0, 100, 1, function(v) return string.format("%d %%", v) end, x, y, hw, off) or chg
  chg = slider("eq_max", "Correction max.", "eq_max", 1, 12, 0.5, function(v) return string.format("± %.1f dB", v) end, x + hw + 20, y, hw, off) or chg
  y = y + 44
  chg = slider("eq_color", "Couleur (sombre ↔ brillant)", "eq_color", -4, 4, 0.5, function(v) return string.format("%+.1f dB", v) end, x, y, w, off) or chg
  y = y + 40
  eq_graph(x, y, w, 96)
  draw_retouch(22, 500, W - 44)

  -------- bas
  local by = H - 46
  if UI.progress then
    col(COL.line); gfx.rect(22, by - 52, W - 44, 6, 1); col(COL.accent); gfx.rect(22, by - 52, math.floor((W - 44) * UI.progress), 6, 1)
  end
  if UI.stats then text(UI.stats, 22, by - 40, COL.ok, 2) end
  text(UI.msg, 22, by - 22, COL.muted, 2)
  main_button(22, by, 190, 30)
  if button("Guide d'utilisation", 332, by, 160, 30) then open_guide() end
  if button("Retirer", 222, by, 100, 30) then
    ST.takes = selected_takes()
    local k = remove_all(ST.takes)
    UI.stats, UI.eq = nil, nil
    set_msg(k > 0 and string.format("Plugin et courbes retirés de %d item%s.", k, k > 1 and "s" or "") or "Rien à retirer sur la sélection.")
  end
  if button("◂ Vue simple", W - 140, by, 118, 30) then resize_to(0); return true end

  if reanalyse then V.clear_cache(); start_analysis()        -- nouvelle fréquence : il faut réécouter l'audio
  elseif chg and not ST.job then
    local any = false
    for _, e in ipairs(ST.takes) do if cache[take_key(e.item, e.take)] then any = true end end
    if any then apply_all() else save() end
  end
  gfx.update()
  return true
end

local function loop()
  local ch = gfx.getchar()
  U.frame()
  if ch < 0 or ch == 27 then save(); return end
  -- la fenêtre du script garde le clavier : on relaie les raccourcis utiles à REAPER
  local cap = gfx.mouse_cap
  if ch == 32 then reaper.Main_OnCommand(40044, 0)                                  -- espace : lecture / stop
  elseif ch == 26 or (ch == 122 and cap & 4 == 4) then                             -- Ctrl/Cmd+Z : annuler (Maj : rétablir)
    reaper.Main_OnCommand(cap & 8 == 8 and 40030 or 40029, 0)
  elseif ch == 25 or (ch == 121 and cap & 4 == 4) then reaper.Main_OnCommand(40030, 0)  -- Ctrl+Y : rétablir
  end
  local down = gfx.mouse_cap & 1 == 1
  clicked = down and not UI.mouse_was
  if UI.skip_click then clicked = false; if not down then UI.skip_click = false end end
  UI.mouse_was = down
  if ST.job then ST.job() else ST.takes = selected_takes() end
  if not draw() then save(); gfx.quit(); return end
  reaper.defer(loop)
end

if #ST.takes == 0 then
  set_msg("Sélectionnez un ou plusieurs items audio (voix), puis « Analyser et appliquer ».")
else
  start_analysis()
end
reaper.defer(loop)
