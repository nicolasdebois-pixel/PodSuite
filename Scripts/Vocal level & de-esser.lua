-- Vocal level & de-esser
-- Nivelle une voix (parlée ou chantée), atténue ses sifflantes, ses plosives et l'effet de proximité,
-- et corrige son équilibre tonal, en écrivant des courbes d'automation et une égalisation sur un
-- petit plugin placé sur la PRISE (avant les effets de la piste).
-- L'analyse lit tout l'item à l'avance : les corrections arrivent pile au bon moment, sans pompage.
-- Les courbes restent collées à l'item : on peut le déplacer ou le couper ensuite.
local TITLE = "Vocal level & de-esser"
local SECTION = "VOCALLEVEL"
local SR = 24000                        -- fréquence d'analyse
local FXDESC = "Vocal level & de-esser (gain"
local scriptpath = ({ reaper.get_action_context() })[2]
local scriptdir = scriptpath:match("^(.*[/\\])")
local SEP = package.config:sub(1, 1)

---------------------------------------------------------------- Réglages
local PRESETS = {
  parole = { amount = 80, range = 8, release = 1200 },
  chant = { amount = 55, range = 6, release = 2000 },
}
local DEF = {
  mode = "parole", auto = 1, target = -20, amount = 80, range = 8, release = 1200,
  de_on = 1, depth = 6, sens = 50, freq = 5500, split = 1,
  plo_on = 1, prox_on = 1, lo_depth = 9, plo_sens = 50, plo_depth = 20, hpf = 60, prox = 90, lowfreq = 200,
  eq_on = 1, eq_amount = 75, eq_color = 0, eq_max = 6,
  rider_on = 1, adv = 0, lv_rider = 2, lv_de = 2, lv_plo = 2, lv_prox = 2, lv_eq = 2,
}
-- Vue simple : trois intensités par traitement (Léger, Moyen, Fort) qui règlent les curseurs avancés
local LEVELS = {
  rider = { { amount = 50, range = 5 }, { amount = 80, range = 8 }, { amount = 95, range = 12 } },
  de = { { depth = 4, sens = 40 }, { depth = 6, sens = 50 }, { depth = 9, sens = 65 } },
  plo = { { plo_sens = 40, plo_depth = 12, hpf = 50 }, { plo_sens = 50, plo_depth = 20, hpf = 60 }, { plo_sens = 65, plo_depth = 28, hpf = 80 } },
  prox = { { lo_depth = 5, prox = 60 }, { lo_depth = 8, prox = 90 }, { lo_depth = 12, prox = 100 } },
  eq = { { eq_amount = 50, eq_max = 4 }, { eq_amount = 75, eq_max = 6 }, { eq_amount = 100, eq_max = 8 } },
}
local S = {}
for k, v in pairs(DEF) do
  local s = reaper.GetExtState(SECTION, k)
  if s == "" then S[k] = v elseif type(v) == "number" then S[k] = tonumber(s) or v else S[k] = s end
end
local function save() for k in pairs(DEF) do reaper.SetExtState(SECTION, k, tostring(S[k]), true) end end

---------------------------------------------------------------- Filtres
local function biquad(kind, f, gain_db, q)
  local w = 2 * math.pi * math.min(f, SR * 0.45) / SR
  local c, s = math.cos(w), math.sin(w)
  local al = s / (2 * (q or 0.7071))
  local b0, b1, b2, a0, a1, a2
  if kind == "hp" then
    b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2; a0, a1, a2 = 1 + al, -2 * c, 1 - al
  elseif kind == "lp" then
    b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2; a0, a1, a2 = 1 + al, -2 * c, 1 - al
  else -- plateau aigu (RBJ)
    local A = 10 ^ (gain_db / 40); local sq = 2 * math.sqrt(A) * al
    b0 = A * ((A + 1) + (A - 1) * c + sq); b1 = -2 * A * ((A - 1) + (A + 1) * c); b2 = A * ((A + 1) + (A - 1) * c - sq)
    a0 = (A + 1) - (A - 1) * c + sq; a1 = 2 * ((A - 1) - (A + 1) * c); a2 = (A + 1) - (A - 1) * c - sq
  end
  return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0, 0, 0 }
end

---------------------------------------------------------------- Prises sélectionnées
local function take_key(item, take)
  local _, g = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
  return table.concat({ g, reaper.GetMediaItemInfo_Value(item, "D_LENGTH"), reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
    reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"), S.freq, S.lowfreq }, "|")
end

local function selected_takes()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tk = reaper.GetActiveTake(it)
    if tk and not reaper.TakeIsMIDI(tk) then list[#list + 1] = { item = it, take = tk } end
  end
  return list
end

local function find_fx(take)
  for i = 0, reaper.TakeFX_GetCount(take) - 1 do
    local _, name = reaper.TakeFX_GetFXName(take, i, "")
    if name:find(FXDESC, 1, true) or name:find("Vocal level.jsfx", 1, true) then return i end
  end
  return -1
end

---------------------------------------------------------------- Analyse
-- Pour chaque prise : niveau (pondéré, fenêtre glissante) toutes les 20 ms,
-- énergie totale et énergie des aigus (au-dessus de la fréquence du de-esser) toutes les 4 ms.
local HOP, FR = 480, 96                 -- 20 ms et 4 ms à 24 kHz
local cache = {}

-- spectre : FFT de 1024 points (≈ 43 ms) toutes les 200 ms, regroupée en tiers d'octave
local NFFT, FFT_EVERY = 1024, 4800
local BANDS = { 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500 }
-- spectre moyen de référence de la voix parlée (tiers d'octave, d'après le spectre moyen international de la parole)
local LTASS = { 54.4, 57.7, 56.8, 60.2, 60.3, 59.0, 62.1, 62.1, 60.5, 56.8, 53.7, 53.0, 52.0, 48.7, 48.1, 46.8, 45.6, 44.5, 44.3, 43.7, 43.4, 41.3 }
local fft_rev, fft_cos, fft_sin, hann, band_bins = {}, {}, {}, {}, {}
do
  local bits = 10
  for i = 0, NFFT - 1 do
    local r, v = 0, i
    for _ = 1, bits do r = (r << 1) | (v & 1); v = v >> 1 end
    fft_rev[i] = r
  end
  for k = 0, NFFT / 2 - 1 do fft_cos[k] = math.cos(-2 * math.pi * k / NFFT); fft_sin[k] = math.sin(-2 * math.pi * k / NFFT) end
  for i = 0, NFFT - 1 do hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (NFFT - 1)) end
  for b, fc in ipairs(BANDS) do
    local lo, hi = fc / 2 ^ (1 / 6), fc * 2 ^ (1 / 6)
    band_bins[b] = { math.max(1, math.floor(lo * NFFT / SR + 0.5)), math.min(NFFT / 2 - 1, math.floor(hi * NFFT / SR + 0.5)) }
  end
end
local function fft_bands(ring, pos)
  local re, im = {}, {}
  for i = 0, NFFT - 1 do
    local x = ring[(pos + i) % NFFT] or 0
    local j = fft_rev[i]
    re[j] = x * hann[i]; im[j] = 0
  end
  local size = 2
  while size <= NFFT do
    local half, step = size // 2, NFFT // size
    for st = 0, NFFT - 1, size do
      for k = 0, half - 1 do
        local c, s = fft_cos[k * step], fft_sin[k * step]
        local a, b = st + k, st + k + half
        local tr = re[b] * c - im[b] * s
        local ti = re[b] * s + im[b] * c
        re[b] = re[a] - tr; im[b] = im[a] - ti
        re[a] = re[a] + tr; im[a] = im[a] + ti
      end
    end
    size = size * 2
  end
  local out = {}
  for b = 1, #BANDS do
    local sum = 0
    for k = band_bins[b][1], band_bins[b][2] do sum = sum + re[k] * re[k] + im[k] * im[k] end
    out[b] = sum
  end
  return out
end

local function analyse_take(e, on_progress)
  local item, take = e.item, e.take
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local fx = find_fx(take)
  local was = fx >= 0 and reaper.TakeFX_GetEnabled(take, fx)
  if fx >= 0 then reaper.TakeFX_SetEnabled(take, fx, false) end      -- on analyse le son d'origine
  local acc = reaper.CreateTakeAudioAccessor(take)
  local nch = math.max(1, math.min(2, reaper.GetMediaSourceNumChannels(reaper.GetMediaItemTake_Source(take))))
  local total = math.floor(len * SR)
  local BLOCK = SR
  local buf = reaper.new_array(BLOCK * nch)
  local k1, k2 = biquad("hp", 70), biquad("hs", 1500, 4, 0.7071)
  local h1, h2 = biquad("hp", S.freq), biquad("hp", S.freq)
  local l1, l2 = biquad("lp", S.lowfreq), biquad("lp", S.lowfreq)
  local m1, m2 = biquad("lp", 80), biquad("lp", 80)          -- sub : bande des plosives (sous la voix, même grave)
  local lv, fe, he, le, pe = {}, {}, {}, {}, {}      -- énergies par bloc de 20 ms / trames de 4 ms
  local accK, nK, accF, accH, accL, accP, nF = 0, 0, 0, 0, 0, 0, 0
  local ring, rpos, nS, specs = {}, 0, 0, {}
  local done = 0
  return function(cmd)
    if cmd == "cancel" then                                   -- analyse interrompue : on rend l'item comme on l'a trouvé
      reaper.DestroyAudioAccessor(acc)
      if fx >= 0 then reaper.TakeFX_SetEnabled(take, fx, was) end
      return true
    end
    local deadline = reaper.time_precise() + 0.04
    while done < total and reaper.time_precise() < deadline do
      local n = math.min(BLOCK, total - done)
      buf.clear()
      reaper.GetAudioAccessorSamples(acc, SR, nch, done / SR, n, buf)
      local t = buf.table(1, n * nch)
      local a1, a2, a3, a4, a5, z1, z2 = k1[1], k1[2], k1[3], k1[4], k1[5], k1[6], k1[7]
      local b1, b2, b3, b4, b5, y1, y2 = k2[1], k2[2], k2[3], k2[4], k2[5], k2[6], k2[7]
      local c1, c2, c3, c4, c5, u1, u2 = h1[1], h1[2], h1[3], h1[4], h1[5], h1[6], h1[7]
      local d1, d2, d3, d4, d5, v1, v2 = h2[1], h2[2], h2[3], h2[4], h2[5], h2[6], h2[7]
      local e1, e2, e3, e4, e5, w1, w2 = l1[1], l1[2], l1[3], l1[4], l1[5], l1[6], l1[7]
      local f1, f2, f3, f4, f5, q1, q2 = l2[1], l2[2], l2[3], l2[4], l2[5], l2[6], l2[7]
      local g1, g2, g3, g4, g5, r1, r2 = m1[1], m1[2], m1[3], m1[4], m1[5], m1[6], m1[7]
      local j1, j2, j3, j4, j5, o1, o2 = m2[1], m2[2], m2[3], m2[4], m2[5], m2[6], m2[7]
      for i = 1, n do
        local x
        if nch == 2 then x = (t[2 * i - 1] + t[2 * i]) * 0.5 else x = t[i] end
        -- pondération (passe-haut 70 Hz + plateau +4 dB au-dessus de 1,5 kHz)
        local p = a1 * x + z1; z1 = a2 * x - a4 * p + z2; z2 = a3 * x - a5 * p
        local k = b1 * p + y1; y1 = b2 * p - b4 * k + y2; y2 = b3 * p - b5 * k
        -- aigus (passe-haut 4e ordre à la fréquence du de-esser)
        local hh = c1 * p + u1; u1 = c2 * p - c4 * hh + u2; u2 = c3 * p - c5 * hh
        local h = d1 * hh + v1; v1 = d2 * hh - d4 * h + v2; v2 = d3 * hh - d5 * h
        -- niveau du rider : bande vocale SOUS la fréquence du de-esser (les sifflantes ne font pas baisser la voix)
        local lo = k - h
        accK = accK + lo * lo; nK = nK + 1
        -- graves (passe-bas 4e ordre sur le son brut : les plosives descendent sous 70 Hz)
        local ll = e1 * x + w1; w1 = e2 * x - e4 * ll + w2; w2 = e3 * x - e5 * ll
        local l = f1 * ll + q1; q1 = f2 * ll - f4 * l + q2; q2 = f3 * ll - f5 * l
        local pp = g1 * x + r1; r1 = g2 * x - g4 * pp + r2; r2 = g3 * x - g5 * pp
        local pl = j1 * pp + o1; o1 = j2 * pp - j4 * pl + o2; o2 = j3 * pp - j5 * pl
        accF = accF + p * p; accH = accH + h * h; accL = accL + l * l; accP = accP + pl * pl; nF = nF + 1
        if nF == FR then
          fe[#fe + 1] = accF / FR; he[#he + 1] = accH / FR; le[#le + 1] = accL / FR; pe[#pe + 1] = accP / FR
          accF, accH, accL, accP, nF = 0, 0, 0, 0, 0
        end
        ring[rpos] = x; rpos = (rpos + 1) % NFFT; nS = nS + 1
        if nS % FFT_EVERY == 0 and nS >= NFFT then
          local e = 0
          for j = 0, NFFT - 1 do local v = ring[j]; e = e + v * v end
          specs[#specs + 1] = { e = e / NFFT, b = fft_bands(ring, rpos), t = (nS - NFFT / 2) / SR }
        end
        if nK == HOP then lv[#lv + 1] = accK / HOP; accK, nK = 0, 0 end
      end
      k1[6], k1[7], k2[6], k2[7], h1[6], h1[7], h2[6], h2[7] = z1, z2, y1, y2, u1, u2, v1, v2
      l1[6], l1[7], l2[6], l2[7] = w1, w2, q1, q2
      m1[6], m1[7], m2[6], m2[7] = r1, r2, o1, o2
      done = done + n
    end
    if on_progress then on_progress(done / math.max(1, total)) end
    if done < total then return false end
    reaper.DestroyAudioAccessor(acc)
    if fx >= 0 then reaper.TakeFX_SetEnabled(take, fx, was) end
    return true, { len = len, lv = lv, fe = fe, he = he, le = le, pe = pe, specs = specs }
  end
end

---------------------------------------------------------------- Calcul des courbes
local function db(e) return 10 * math.log(e + 1e-12, 10) end
local function pct(arr, p)
  local s = {}
  for i = 1, #arr do s[i] = arr[i] end
  table.sort(s)
  if #s == 0 then return -90 end
  return s[math.max(1, math.min(#s, math.floor(#s * p + 0.5)))]
end

-- Simplification (Ramer-Douglas-Peucker) : garde les points utiles à 0,25 dB près
local function simplify(pts, tol)
  if #pts <= 2 then return pts end
  local keep = { [1] = true, [#pts] = true }
  local stack = { { 1, #pts } }
  while #stack > 0 do
    local a, b = table.unpack(table.remove(stack))
    local ta, va, tb, vb = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
    local best, bi = 0, nil
    for i = a + 1, b - 1 do
      local v = va + (vb - va) * (pts[i][1] - ta) / (tb - ta)
      local d = math.abs(pts[i][2] - v)
      if d > best then best = d; bi = i end
    end
    if bi and best > tol then keep[bi] = true; stack[#stack + 1] = { a, bi }; stack[#stack + 1] = { bi, b } end
  end
  local out = {}
  for i = 1, #pts do if keep[i] then out[#out + 1] = pts[i] end end
  return out
end

local function rider_curve(A)
  if S.rider_on ~= 1 then return { { 0, 0 } }, 0, 0, nil end
  local win = math.max(1, math.floor((S.mode == "chant" and 0.3 or 0.4) / 0.02 + 0.5))
  local L, n = {}, #A.lv
  local run = 0
  for i = 1, n do
    run = run + A.lv[i]
    if i > win then run = run - A.lv[i - win] end
    L[i] = db(run / math.min(i, win))
  end
  -- le niveau d'une trame décrit la fenêtre qui se termine là : on le recentre
  local Lc = {}
  for i = 1, n do Lc[i] = L[math.min(n, i + win // 2)] end
  -- bruit de fond : les blocs de 20 ms les plus calmes (respirations, silences entre les phrases)
  local raw = {}
  for i = 1, n do raw[i] = db(A.lv[i]) end
  local floor = pct(raw, 0.03)
  local hi = pct(Lc, 0.95)
  local gate = math.max(floor + 10, hi - 35)
  local voiced, vl = {}, {}
  for i = 1, n do voiced[i] = Lc[i] > gate; if voiced[i] then vl[#vl + 1] = Lc[i] end end
  if #vl == 0 then return { { 0, 0 }, { A.len, 0 } }, 0, 0, nil end
  local T = (S.auto == 1) and pct(vl, 0.5) or S.target
  -- Deux étages, comme un ingénieur qui « ride » : le niveau de la PHRASE (≈ 1,5 s, voix seulement) décide du gain,
  -- et seules les vraies pointes (plus de 4 dB au-dessus de la phrase) sont rattrapées vite.
  -- Suivre le niveau syllabe par syllabe ferait pomper.
  local Ws = math.floor((S.mode == "chant" and 2.5 or 1.5) / 0.02 + 0.5)
  -- phrases : suites de voix séparées par des pauses d'au moins 0,35 s ; la moyenne ne déborde pas sur la phrase voisine
  local seg, sid, gapn = {}, 0, 99
  for i = 1, n do
    if voiced[i] then
      if gapn >= 18 then sid = sid + 1 end
      gapn = 0
    else gapn = gapn + 1 end
    seg[i] = sid
  end
  local cs, cc = { [0] = 0 }, { [0] = 0 }
  for i = 1, n do
    cs[i] = cs[i - 1] + (voiced[i] and A.lv[i] or 0)
    cc[i] = cc[i - 1] + (voiced[i] and 1 or 0)
  end
  local sstart, send = {}, {}
  for i = 1, n do
    if voiced[i] then
      local k = seg[i]
      sstart[k] = sstart[k] or i; send[k] = i
    end
  end
  local Lp = {}
  for i = 1, n do
    local k = seg[i]
    local a0, b0 = i - Ws // 2, i + Ws // 2
    if sstart[k] then a0 = math.max(a0, sstart[k]); b0 = math.min(b0, send[k]) end
    a0 = math.max(1, a0); b0 = math.min(n, math.max(b0, a0))
    local c = cc[b0] - cc[a0 - 1]
    Lp[i] = c > 0 and db((cs[b0] - cs[a0 - 1]) / c) or Lc[i]
  end
  local g = {}
  for i = 1, n do
    if voiced[i] then
      local slow = (T - Lp[i]) * S.amount / 100
      local peak = math.max(0, Lc[i] - Lp[i] - 4) * S.amount / 100
      g[i] = math.max(-S.range, math.min(S.range, slow - peak))
    end
  end
  -- Comportement façon compresseur optique (LA-2A) : la réduction arrive vite, le retour se fait en deux temps
  -- (rapide sur la première moitié, puis lent, d'autant plus lent que la réduction a duré : « mémoire » de la cellule).
  -- Comme l'analyse connaît la suite, les grands changements se font PENDANT LES PAUSES, là où on ne les entend pas.
  local dt = 0.02
  local prevv, nextv = {}, {}
  local pv = nil
  for i = 1, n do if voiced[i] then pv = i end; prevv[i] = pv end
  local nx = nil
  for i = n, 1, -1 do if voiced[i] then nx = i end; nextv[i] = nx end
  local att_k = math.exp(-dt / 0.015)
  local fast_k = math.exp(-dt / 0.06)
  local first = nextv[1]
  local y = first and g[first] or 0
  local rel_from, held, rel_held = nil, 0, 0
  local out = {}
  for i = 1, n do
    if not voiced[i] then
      local p0, p1 = prevv[i], nextv[i]
      local plen = ((p1 or (n + 1)) - (p0 or 0) - 1) * dt
      if plen >= 0.25 then
        local t2 = p1 and g[p1] or math.min(0, y)
        -- long silence : pas de gain positif au milieu (le bruit de fond ne monte pas), on rejoint la phrase suivante juste avant
        if plen >= 1.0 and (not p1 or (p1 - i) * dt > 0.3) then t2 = math.min(0, t2) end
        y = y + (t2 - y) * (1 - math.exp(-dt / 0.08))
        rel_from, held = nil, 0
      end
      out[i] = y
    else
      local tgt = g[i]
      if tgt < y then
        y = tgt + (y - tgt) * att_k
        held = held + dt; rel_from = nil
      else
        if not rel_from then rel_from = y; rel_held = held; held = 0 end
        local slow = S.release / 1000 * (1 + math.min(rel_held, 3) / 3)
        local k = ((y - rel_from) < 0.5 * (tgt - rel_from)) and fast_k or math.exp(-dt / slow)
        y = tgt + (y - tgt) * k
        if tgt - y < 0.05 then rel_from = nil end
      end
      out[i] = y
    end
  end
  -- anticipation de 40 ms : la réduction est en place quand la syllabe forte commence
  local sm, gmin, gmax = {}, 0, 0
  for i = 1, n do
    sm[i] = out[math.min(n, i + 2)]
    if sm[i] < gmin then gmin = sm[i] end
    if sm[i] > gmax then gmax = sm[i] end
  end
  local pts = {}
  for i = 1, n do pts[#pts + 1] = { (i - 0.5) * 0.02, sm[i] } end
  return simplify(pts, 0.25), gmin, gmax, T
end

local function deess_curve(A)
  if S.de_on ~= 1 or S.depth <= 0 then return {}, 0 end
  local n = #A.fe
  local fd, hd = {}, {}
  for i = 1, n do fd[i] = db(A.fe[i]); hd[i] = db(A.he[i]) end
  local floor = pct(fd, 0.10)
  local loud = {}
  for i = 1, n do if fd[i] > floor + 15 then loud[#loud + 1] = hd[i] end end
  if #loud == 0 then return {}, 0 end
  local href = pct(loud, 0.5)                           -- niveau habituel des aigus de cette voix
  local s = S.sens / 100
  local ratio_thr = -4 - 8 * s                          -- part des aigus dans le son (sensibilité 50 : -8 dB)
  local level_thr = href + 8 - 8 * s                    -- aigus au-dessus de leur niveau habituel (+4 dB)
  local sib = {}
  for i = 1, n do
    sib[i] = fd[i] > floor + 10 and (hd[i] - fd[i]) > ratio_thr and hd[i] > level_thr
  end
  local pts, count = {}, 0
  local i = 1
  local dt = FR / SR
  while i <= n do
    if sib[i] then
      local j = i
      while j + 1 <= n and (sib[j + 1] or (j + 3 <= n and (sib[j + 2] or sib[j + 3]))) do j = j + 1 end
      if j - i + 1 >= 3 then                            -- au moins 12 ms
        local peak = 0
        for k = i, j do local r = hd[k] - href; if r > peak then peak = r end end
        local r = math.min(S.depth, math.max(2, peak))
        local t0, t1 = (i - 1) * dt, j * dt
        local last = pts[#pts]
        if last and t0 - 0.006 <= last[1] then table.remove(pts) -- sifflantes collées : un seul creux
        else pts[#pts + 1] = { math.max(0, t0 - 0.006), 0 } end
        pts[#pts + 1] = { t0 + 0.002, r }
        pts[#pts + 1] = { math.max(t0 + 0.003, t1 - 0.002), r }
        pts[#pts + 1] = { t1 + 0.010, 0 }
        count = count + 1
      end
      i = j + 1
    else i = i + 1 end
  end
  return pts, count
end

---------------------------------------------------------------- Graves : plosives et effet de proximité
-- Renvoie l'atténuation des graves (dB, positive) sous forme de points, et le nombre de plosives.
local function graves_curve(A)
  if S.prox_on ~= 1 or S.lo_depth <= 0 then return {}, 0, 0 end
  local n = math.min(#A.le, #A.fe)
  if n < 10 then return {}, 0, 0 end
  local L, F = {}, {}
  for i = 1, n do L[i] = db(A.le[i]); F[i] = db(A.fe[i]) end
  local floor = pct(F, 0.03)
  local hi = pct(F, 0.95)
  local gate = math.max(floor + 15, hi - 35)
  local voiced, ratios, lows = {}, {}, {}
  -- proximité : part des graves sur 300 ms (moyenne d'énergie), comparée à la part habituelle de cette voix
  local W = 75
  local sl, sf = 0, 0
  local R = {}
  for i = 1, n do
    -- graves comparés au reste de la voix (sans les graves eux-mêmes)
    sl = sl + A.le[i]; sf = sf + math.max(A.fe[i] - A.le[i], A.fe[i] * 0.05)
    if i > W then sl = sl - A.le[i - W]; sf = sf - math.max(A.fe[i - W] - A.le[i - W], A.fe[i - W] * 0.05) end
    R[i] = db(sl) - db(sf)
  end
  local Rc = {}
  for i = 1, n do Rc[i] = R[math.min(n, i + W // 2)] end
  for i = 1, n do
    voiced[i] = F[i] > gate
    if voiced[i] then ratios[#ratios + 1] = Rc[i]; lows[#lows + 1] = L[i] end
  end
  if #ratios == 0 then return {}, 0, 0 end
  -- référence : la voix « à bonne distance » (30e centile : les passages trop proches et les plosives ne la faussent pas)
  local ref = pct(ratios, 0.3)
  local lowref = pct(lows, 0.5)
  local att = {}
  local prox_max = 0
  for i = 1, n do
    -- ×1,4 : un plateau n'atteint sa pleine atténuation que bien en dessous de sa fréquence
    local ex = voiced[i] and math.max(0, Rc[i] - ref - 1) * 1.4 * S.prox / 100 or 0
    att[i] = math.min(S.lo_depth, ex)
  end
  -- lissage (100 ms) : l'effet de proximité varie lentement
  local sig, Rk = 25, 75
  local ker, ks = {}, 0
  for k = -Rk, Rk do ker[k] = math.exp(-(k * k) / (2 * sig * sig)); ks = ks + ker[k] end
  local sm = {}
  for i = 1, n do
    local v = 0
    for k = -Rk, Rk, 3 do v = v + ker[k] * att[math.max(1, math.min(n, i + k))] end
    sm[i] = v * 3 / ks
    if sm[i] > prox_max then prox_max = sm[i] end
  end
  local count = 0
  local pts = {}
  local dt = FR / SR
  for k = 1, n do pts[#pts + 1] = { (k - 0.5) * dt, sm[k] } end
  return simplify(pts, 0.3), count, prox_max, sm
end

---------------------------------------------------------------- Plosives : le sub (sous 80 Hz) comparé au corps de la voix (80–200 Hz)
-- Dans une voix, le sub reste toujours bien en dessous du corps ; une plosive (ou un souffle dans la capsule)
-- l'envoie au-dessus. On baisse le sub de l'excès, avec 12 ms d'anticipation et un retour en 40 ms.
-- La comparaison se fait à l'intérieur du grave : une prise très proche ne fausse donc pas la détection.
-- « already(i) » : ce que les autres traitements retirent déjà dans le sub à cet instant (coupe-bas, égalisation, proximité).
-- On ne retire que la différence : sinon les corrections s'additionnent et creusent un trou dans le grave.
local function sub_curve(A, already)
  if S.plo_on ~= 1 or S.plo_depth <= 0 then return {}, 0 end
  local n = math.min(#A.pe, #A.le, #A.fe)
  if n < 10 then return {}, 0 end
  local F, Sd, R = {}, {}, {}
  for i = 1, n do
    F[i] = db(A.fe[i])
    Sd[i] = db(A.pe[i])
    R[i] = Sd[i] - db(math.max(A.le[i] - A.pe[i], A.le[i] * 0.02))
  end
  local floor, hi = pct(F, 0.03), pct(F, 0.95)
  local gate = math.max(floor + 15, hi - 35)
  local rs, ss = {}, {}
  for i = 1, n do if F[i] > gate then rs[#rs + 1] = R[i]; ss[#ss + 1] = Sd[i] end end
  if #rs == 0 then return {}, 0 end
  local rref = pct(rs, 0.5)
  local sref = pct(ss, 0.5)
  local fv = {}
  for i = 1, n do if F[i] > gate then fv[#fv + 1] = F[i] end end
  local fref = pct(fv, 0.5)                               -- niveau habituel de la voix
  local s = S.plo_sens / 100
  local margin = 18 - 10 * s                              -- sensibilité 50 : 13 dB au-dessus du rapport habituel de cette voix
  -- une plosive est une ATTAQUE : le sub bondit d'au moins ~9 dB au-dessus de son propre niveau des 40 ms précédentes
  local jump = 12 - 6 * s
  local att = {}
  for i = 1, n do att[i] = 0 end
  local i = 11
  while i <= n do
    local base = math.huge
    for k = i - 10, i - 2 do if Sd[k] < base then base = Sd[k] end end
    -- … et assez fort pour s'entendre : proche du niveau de la voix elle-même (un grondement de fond ne compte pas)
    if Sd[i] - base >= jump and R[i] - rref - margin > 0 and Sd[i] > sref + 8 and Sd[i] > fref - 8 + 8 * (1 - s) then
      local peak, j = Sd[i], i
      while j + 1 <= n and j - i < 30 and Sd[j + 1] > peak - 9 do j = j + 1; if Sd[j] > peak then peak = Sd[j] end end
      for k = i, j do
        local ex = R[k] - rref - (margin - 4)
        if ex > 0 then att[k] = math.min(S.plo_depth, ex * 1.5) end
      end
      i = j + 1
    else i = i + 1 end
  end
  local rel = math.exp(-(FR / SR) / 0.04)
  local out, y, count, last_on, prev = {}, 0, 0, -1e9, 0
  for i = 1, n do
    local a = 0
    for k = i, math.min(n, i + 3) do if att[k] > a then a = att[k] end end
    if a >= y then y = a else y = math.max(a, y * rel) end
    local eff = math.max(0, y - (already and already(i) or 0))
    if eff >= 4 and prev < 4 and (i - last_on) * FR / SR > 0.08 then count = count + 1 end
    if eff >= 4 then last_on = i end
    prev = eff
    out[i] = eff
  end
  local pts = {}
  local dt = FR / SR
  for i = 1, n do pts[#pts + 1] = { (i - 0.5) * dt, out[i] } end
  return simplify(pts, 0.4), count
end

---------------------------------------------------------------- Égalisation : spectre mesuré → correction sur 7 bandes
local EQB = { { 1, 100, 0.7 }, { 0, 220, 1 }, { 0, 450, 1 }, { 0, 900, 1 }, { 0, 1800, 1 }, { 0, 3600, 1 }, { 2, 8000, 0.7 } }
local function eq_db(type_, f0, g, q, f)                -- réponse (dB) d'un filtre RBJ à 48 kHz
  local fs = 48000
  local A = 10 ^ (g / 40); local w = 2 * math.pi * f0 / fs; local c, sn = math.cos(w), math.sin(w); local al = sn / (2 * q)
  local b0, b1, b2, a0, a1, a2
  if type_ == 0 then
    b0, b1, b2, a0, a1, a2 = 1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A
  else
    local sq = 2 * math.sqrt(A) * al
    if type_ == 1 then
      b0 = A * ((A + 1) - (A - 1) * c + sq); b1 = 2 * A * ((A - 1) - (A + 1) * c); b2 = A * ((A + 1) - (A - 1) * c - sq)
      a0 = (A + 1) + (A - 1) * c + sq; a1 = -2 * ((A - 1) + (A + 1) * c); a2 = (A + 1) + (A - 1) * c - sq
    else
      b0 = A * ((A + 1) + (A - 1) * c + sq); b1 = -2 * A * ((A - 1) + (A + 1) * c); b2 = A * ((A + 1) + (A - 1) * c - sq)
      a0 = (A + 1) - (A - 1) * c + sq; a1 = 2 * ((A - 1) - (A + 1) * c); a2 = (A + 1) - (A - 1) * c - sq
    end
  end
  local wf = 2 * math.pi * f / fs
  local c1, s1, c2, s2 = math.cos(wf), math.sin(wf), math.cos(2 * wf), math.sin(2 * wf)
  local nr, ni = b0 + b1 * c1 + b2 * c2, -(b1 * s1 + b2 * s2)
  local dr, di = a0 + a1 * c1 + a2 * c2, -(a1 * s1 + a2 * s2)
  return 10 * math.log((nr * nr + ni * ni) / (dr * dr + di * di), 10)
end
local function eq_response(gains, f)
  local r = 0
  for b, e in ipairs(EQB) do if math.abs(gains[b]) > 0.01 then r = r + eq_db(e[1], e[2], gains[b], e[3], f) end end
  return r
end

local function target_curve()
  local t = {}
  for k, f in ipairs(BANDS) do
    local v = LTASS[k]
    local oct = math.log(f / 1000, 2)
    if S.mode == "chant" then v = v + math.max(0, math.min(1, (oct + 0.5) / 2)) * 2.5 end   -- formant du chanteur, plus de brillance
    v = v + S.eq_color * math.max(-1 / 3, math.min(1, oct / 3))                             -- couleur : sombre ↔ brillant
    t[k] = v
  end
  return t
end

-- Renvoie les 7 gains (dB) et, pour l'affichage, le spectre mesuré et la cible (alignés)
-- prox_sm : courbe de l'effet de proximité ; les passages trop proches sont exclus de la mesure,
-- pour que l'égalisation règle la voix « à bonne distance » et que la proximité corrige le reste (sans double correction).
local function eq_fit(A, prox_sm)
  local zero = { 0, 0, 0, 0, 0, 0, 0 }
  local sp = A.specs or {}
  if #sp < 3 then return zero end
  local ed = {}
  for i, b in ipairs(sp) do ed[i] = db(b.e) end
  local floor, hi = pct(ed, 0.05), pct(ed, 0.95)
  local gate = math.max(floor + 15, hi - 30)
  local sum, cnt = {}, 0
  for k = 1, #BANDS do sum[k] = 0 end
  local dtf = FR / SR
  for i, b in ipairs(sp) do
    local close = prox_sm and b.t and (prox_sm[math.max(1, math.floor(b.t / dtf) + 1)] or 0) > 1
    if ed[i] > gate and not close then
      cnt = cnt + 1
      for k = 1, #BANDS do sum[k] = sum[k] + b.b[k] end
    end
  end
  if cnt < 3 then return zero end
  local m, t = {}, target_curve()
  for k = 1, #BANDS do m[k] = db(sum[k] / cnt) end
  local off, no = 0, 0
  for k, f in ipairs(BANDS) do if f >= 250 and f <= 4000 then off = off + (m[k] - t[k]); no = no + 1 end end
  off = off / no
  for k = 1, #BANDS do m[k] = m[k] - off end
  local d = {}
  for k = 1, #BANDS do d[k] = t[k] - m[k] end
  local ds = {}
  for k = 1, #BANDS do ds[k] = (d[math.max(1, k - 1)] + 2 * d[k] + d[math.min(#BANDS, k + 1)]) / 4 end
  for k, f in ipairs(BANDS) do
    -- zone de tolérance : sous 250 Hz, les voix graves et aiguës diffèrent naturellement de ±4 dB (on ne corrige que le surplus)
    local tol = f <= 250 and 4 or 1
    ds[k] = (ds[k] > 0 and 1 or -1) * math.max(0, math.abs(ds[k]) - tol)
    if f < 125 then ds[k] = math.min(ds[k], 0) end           -- on ne remonte jamais l'infra-grave (bruits, vibrations)
    if f >= 10000 then ds[k] = math.min(ds[k], 3) end        -- ni l'extrême aigu (souffle)
    ds[k] = math.max(-S.eq_max, math.min(S.eq_max, ds[k])) * S.eq_amount / 100
  end
  -- moindres carrés : quelle combinaison des 7 filtres approche le mieux la correction voulue ?
  local NB = #EQB
  local Sm = {}
  for b = 1, NB do Sm[b] = {} for k, f in ipairs(BANDS) do Sm[b][k] = eq_db(EQB[b][1], EQB[b][2], 1, EQB[b][3], f) end end
  local function solve(dd)
    local M, v = {}, {}
    for i = 1, NB do
      M[i] = {}
      for j = 1, NB do
        local acc = (i == j) and 0.3 or 0
        for k = 1, #BANDS do acc = acc + Sm[i][k] * Sm[j][k] end
        M[i][j] = acc
      end
      local acc = 0
      for k = 1, #BANDS do acc = acc + Sm[i][k] * dd[k] end
      v[i] = acc
    end
    for c = 1, NB do                                        -- élimination de Gauss
      local piv = c
      for r = c + 1, NB do if math.abs(M[r][c]) > math.abs(M[piv][c]) then piv = r end end
      M[c], M[piv] = M[piv], M[c]; v[c], v[piv] = v[piv], v[c]
      for r = c + 1, NB do
        local fct = M[r][c] / M[c][c]
        for j = c, NB do M[r][j] = M[r][j] - fct * M[c][j] end
        v[r] = v[r] - fct * v[c]
      end
    end
    local g = {}
    for r = NB, 1, -1 do
      local acc = v[r]
      for j = r + 1, NB do acc = acc - M[r][j] * g[j] end
      g[r] = acc / M[r][r]
    end
    return g
  end
  local g = solve(ds)
  -- les filtres ne sont pas tout à fait linéaires en dB : deux passes de correction du résidu
  for _ = 1, 2 do
    local res = {}
    for k, f in ipairs(BANDS) do res[k] = ds[k] - eq_response(g, f) end
    local dg = solve(res)
    for b = 1, NB do g[b] = g[b] + dg[b] end
  end
  -- la courbe finale ne doit jamais dépasser la correction maximale choisie (les filtres voisins s'additionnent)
  local lim = S.eq_max * S.eq_amount / 100
  local peak = 0
  for i = 0, 60 do
    local f = 60 * (14000 / 60) ^ (i / 60)
    local r = math.abs(eq_response(g, f))
    if r > peak then peak = r end
  end
  if peak > lim and peak > 0 then for b = 1, NB do g[b] = g[b] * lim / peak end end
  for b = 1, NB do g[b] = math.max(-12, math.min(12, math.floor(g[b] * 10 + 0.5) / 10)) end
  return g, m, t, ds
end

---------------------------------------------------------------- Écriture dans REAPER
local function jsfx_name()
  -- ReaPack installe le plugin dans Effects/<dépôt>/<catégorie>/ ; on retrouve ce chemin depuis celui du script
  local res = reaper.GetResourcePath()
  local rel = scriptdir:sub(#res + 2):gsub("\\", "/")
  local inst = rel:match("^Scripts/(.*)$")
  local cands = {}
  if inst then cands[#cands + 1] = inst .. "Vocal level.jsfx" end
  cands[#cands + 1] = "Vocal level.jsfx"
  for _, c in ipairs(cands) do
    local f = io.open(res .. "/Effects/" .. c, "rb")
    if f then f:close(); return "JS:" .. c end
  end
  -- copie de secours (installation sans ReaPack) : le plugin est livré à côté du script
  local src = io.open(scriptdir .. "Vocal level.jsfx", "rb") or io.open(scriptdir .. ".." .. SEP .. "Effects" .. SEP .. "Vocal level.jsfx", "rb")
  if src then
    local data = src:read("a"); src:close()
    reaper.RecursiveCreateDirectory(res .. SEP .. "Effects", 0)
    local f = io.open(res .. SEP .. "Effects" .. SEP .. "Vocal level.jsfx", "wb")
    if f then f:write(data); f:close(); return "JS:Vocal level.jsfx" end
  end
end

local function show_env(env)
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if ok then
    local c2 = chunk:gsub("\nVIS %d", "\nVIS 1"):gsub("\nACT %d", "\nACT 1")
    if c2 ~= chunk then reaper.SetEnvelopeStateChunk(env, c2, false) end
  end
end

local function write_env(env, pts, conv, len)
  reaper.DeleteEnvelopePointRange(env, -1, len + 1)
  for _, p in ipairs(pts) do
    if p[1] >= 0 and p[1] <= len then reaper.InsertEnvelopePoint(env, p[1], conv(p[2]), 0, 0, false, true) end
  end
  reaper.Envelope_SortPoints(env)
  show_env(env)
end

---------------------------------------------------------------- Retouches locales
-- Une retouche = une zone de la prise + un réglage (plosive, sifflante ou niveau).
-- Elles sont mémorisées dans la prise (temps de la source audio, donc insensibles au déplacement
-- ou au rognage de l'item) et réappliquées par-dessus les courbes automatiques à chaque calcul.
local RET = {
  plo = { name = "Plosive", steps = { 6, 12, 18, 24 }, mn = 0, mx = 30, fade = 0.010, desc = "coupe le sub (bouffée d'air)" },
  de  = { name = "Sifflante", steps = { 3, 6, 9, 12 }, mn = 0, mx = 24, fade = 0.010, desc = "adoucit les aigus" },
  lvl = { name = "Niveau", steps = { -3, -1, 1, 3 }, mn = -24, mx = 24, fade = 0.030, desc = "baisse ou remonte la zone" },
}
local RET_ORDER = { "plo", "de", "lvl" }
local RET_KEY = "P_EXT:VL_RETOUCHES"

local function get_ret(take)
  local ok, s = reaper.GetSetMediaItemTakeInfo_String(take, RET_KEY, "", false)
  local list = {}
  if not ok or type(s) ~= "string" then return list end
  for k, a, b, d in s:gmatch("(%a+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)") do
    a, b, d = tonumber(a), tonumber(b), tonumber(d)
    if RET[k] and a and b and d and b > a then list[#list + 1] = { k = k, a = a, b = b, d = d } end
  end
  return list
end

local function set_ret(take, list)
  local t = {}
  for _, r in ipairs(list) do t[#t + 1] = string.format("%s %.4f %.4f %.2f", r.k, r.a, r.b, r.d) end
  reaper.GetSetMediaItemTakeInfo_String(take, RET_KEY, table.concat(t, ";"), true)
end

-- zone de la sélection temporelle sur cette prise, en temps de la source (nil si elle ne la touche pas)
local function sel_zone(e)
  local s, t = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if not s or not t or t - s < 0.005 then return nil end
  local pos = reaper.GetMediaItemInfo_Value(e.item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(e.item, "D_LENGTH")
  local a, b = math.max(s, pos) - pos, math.min(t, pos + len) - pos
  if b - a < 0.005 then return nil end
  local off = reaper.GetMediaItemTakeInfo_Value(e.take, "D_STARTOFFS")
  return a + off, b + off
end

-- ajoute d dB (avec une courte rampe de part et d'autre) à une courbe {t, valeur}, sans toucher au reste
local function add_zone(pts, a, b, d, f, mn, mx)
  table.sort(pts, function(p, q) return p[1] < q[1] end)
  local function val(t)
    if #pts == 0 then return 0 end
    if t <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
      if t <= pts[i][1] then
        local p, q = pts[i - 1], pts[i]
        local span = q[1] - p[1]
        return span > 0 and p[2] + (q[2] - p[2]) * (t - p[1]) / span or q[2]
      end
    end
    return pts[#pts][2]
  end
  local function w(t)
    if t <= a - f or t >= b + f then return 0 end
    if t < a then return (t - (a - f)) / f end
    if t > b then return ((b + f) - t) / f end
    return 1
  end
  local out, ts = {}, { a - f, a, b, b + f }
  for _, p in ipairs(pts) do
    if p[1] < a - f or p[1] > b + f then out[#out + 1] = p else ts[#ts + 1] = p[1] end
  end
  table.sort(ts)
  local last
  for _, t in ipairs(ts) do
    if t ~= last then
      out[#out + 1] = { math.max(0, t), math.max(mn, math.min(mx, val(t) + d * w(t))) }
      last = t
    end
  end
  table.sort(out, function(p, q) return p[1] < q[1] end)
  return out
end

local function apply_take(e, A)
  local take = e.take
  local fx = find_fx(take)
  if fx < 0 then
    local name = jsfx_name()
    if not name then return false, "plugin introuvable" end
    fx = reaper.TakeFX_AddByName(take, name, 1)
    if fx < 0 then return false, "plugin introuvable" end
    reaper.TakeFX_SetOpen(take, fx, false)
  end
  reaper.TakeFX_SetEnabled(take, fx, true)            -- un réglage modifié sort du bypass : on entend le résultat
  reaper.TakeFX_SetParamNormalized(take, fx, 2, (S.freq - 3000) / 7000)
  reaper.TakeFX_SetParamNormalized(take, fx, 3, S.split)
  reaper.TakeFX_SetParamNormalized(take, fx, 5, (S.lowfreq - 60) / 340)
  local hpf = S.plo_on == 1 and S.hpf or 0
  reaper.TakeFX_SetParamNormalized(take, fx, 14, hpf / 150)
  local rpts, gmin, gmax = rider_curve(A)
  local dpts, count = deess_curve(A)
  local lpts, _, prox, prox_sm = graves_curve(A)
  local gains, m, t, want = { 0, 0, 0, 0, 0, 0, 0 }, nil, nil, nil
  if S.eq_on == 1 then gains, m, t, want = eq_fit(A, prox_sm) end
  -- ce qui est déjà retiré vers 50 Hz : égalisation + coupe-bas (fixes), proximité (variable)
  local static_cut = -eq_response(gains, 50)
  if hpf > 0 then static_cut = static_cut - 10 * math.log((50 / hpf) ^ 4 / (1 + (50 / hpf) ^ 4), 10) end
  static_cut = math.max(0, static_cut)
  local spts, plos = sub_curve(A, function(i) return static_cut + 0.9 * ((prox_sm and prox_sm[i]) or 0) end)
  for b = 1, 7 do reaper.TakeFX_SetParamNormalized(take, fx, 5 + b, (gains[b] + 12) / 24) end
  -- retouches locales, par-dessus les courbes automatiques
  local nret = 0
  local off = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  for _, r in ipairs(get_ret(take)) do
    local R, a, b = RET[r.k], r.a - off, r.b - off
    if b > 0 and a < A.len then
      if r.k == "plo" then spts = add_zone(spts, a, b, r.d, R.fade, R.mn, R.mx)
      elseif r.k == "de" then dpts = add_zone(dpts, a, b, r.d, R.fade, R.mn, R.mx)
      else rpts = add_zone(rpts, a, b, r.d, R.fade, R.mn, R.mx) end
      nret = nret + 1
    end
  end
  local er = reaper.TakeFX_GetEnvelope(take, fx, 0, true)
  local ed = reaper.TakeFX_GetEnvelope(take, fx, 1, true)
  local el = reaper.TakeFX_GetEnvelope(take, fx, 4, true)
  if er then write_env(er, rpts, function(v) return (v + 24) / 48 end, A.len) end
  if ed then
    if #dpts == 0 then dpts = { { 0, 0 } } end
    write_env(ed, dpts, function(v) return v / 24 end, A.len)
  end
  if el then
    if #lpts == 0 then lpts = { { 0, 0 } } end
    write_env(el, lpts, function(v) return v / 24 end, A.len)
  end
  local es = reaper.TakeFX_GetEnvelope(take, fx, 13, true)
  if es then
    if #spts == 0 then spts = { { 0, 0 } } end
    write_env(es, spts, function(v) return v / 30 end, A.len)
  end
  return true, { gmin = gmin, gmax = gmax, sib = count, plos = plos, prox = prox, gains = gains, m = m, t = t, want = want, ret = nret }
end

local function remove_all(list)
  reaper.Undo_BeginBlock()
  local n = 0
  for _, e in ipairs(list) do
    local fx = find_fx(e.take)
    if fx >= 0 then reaper.TakeFX_Delete(e.take, fx); n = n + 1 end
    if #get_ret(e.take) > 0 then set_ret(e.take, {}) end
  end
  reaper.Undo_EndBlock(TITLE .. " : retrait", -1)
  reaper.UpdateArrange()
  return n
end

---------------------------------------------------------------- Interface
local AW, AH, SW, SH = 940, 750, 680, 720
local W, H = AW, AH
if S.adv ~= 1 then W, H = SW, SH end
local U = dofile(scriptdir .. "Toolbox_ui.lua")
U.init(TITLE, W, H)
local UI = { msg = "", progress = nil, drag = nil, mouse_was = false, stats = nil }
local takes = selected_takes()
local job = nil                                   -- analyse en cours
local cancel_job = nil
local function set_msg(m) UI.msg = m end

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

local function apply_all()
  local ok_n, err, gmin, gmax, sib, plos, nret = 0, nil, 0, 0, 0, 0, 0
  UI.eq = nil
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, e in ipairs(takes) do
    local A = cache[take_key(e.item, e.take)]
    if A then
      local ok, r = apply_take(e, A)
      if ok then
        ok_n = ok_n + 1
        gmin = math.min(gmin, r.gmin); gmax = math.max(gmax, r.gmax); sib = sib + r.sib; plos = plos + r.plos; nret = nret + (r.ret or 0)
        if not UI.eq and r.m then UI.eq = r end                -- courbe d'égalisation du premier item, pour l'affichage
      else err = r end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(TITLE, -1)
  reaper.UpdateArrange()
  save()
  if err and ok_n == 0 then
    set_msg("Plugin « Vocal level » introuvable : réinstallez le paquet avec ReaPack.")
  else
    local parts = {}
    if S.rider_on == 1 then parts[#parts + 1] = string.format("niveau corrigé de %+.0f à %+.0f dB", gmin, gmax) end
    if S.de_on == 1 then parts[#parts + 1] = string.format("%d sifflante%s", sib, sib > 1 and "s" or "") end
    if S.plo_on == 1 then parts[#parts + 1] = string.format("%d plosive%s", plos, plos > 1 and "s" or "") end
    if S.eq_on == 1 then parts[#parts + 1] = "égalisation appliquée" end
    if nret > 0 then parts[#parts + 1] = string.format("%d retouche%s locale%s", nret, nret > 1 and "s" or "", nret > 1 and "s" or "") end
    UI.stats = #parts > 0 and ("Fait : " .. table.concat(parts, " · ")) or "Tous les traitements sont désactivés."
    set_msg(string.format("%d item%s traité%s. Écoutez, puis ajustez : tout se met à jour à chaque clic.", ok_n, ok_n > 1 and "s" or "", ok_n > 1 and "s" or ""))
  end
end

local function start_analysis()
  takes = selected_takes()
  if #takes == 0 then set_msg("Sélectionnez un ou plusieurs items audio (voix), puis « Analyser et appliquer »."); return end
  local queue = {}
  for _, e in ipairs(takes) do if not cache[take_key(e.item, e.take)] then queue[#queue + 1] = e end end
  if #queue == 0 then apply_all(); return end
  local qi, step = 1, nil
  cancel_job = function()
    if step then step("cancel") end
    job, cancel_job = nil, nil; UI.progress = nil
    set_msg("Analyse annulée : rien n'a été modifié.")
  end
  job = function()
    set_msg(string.format("Analyse… item %d / %d", qi, #queue))
    if not step then step = analyse_take(queue[qi], function(f) UI.progress = (qi - 1 + f) / #queue end) end
    local done, A = step()
    if done then
      cache[take_key(queue[qi].item, queue[qi].take)] = A
      qi = qi + 1; step = nil
      if qi > #queue then job, cancel_job = nil, nil; UI.progress = nil; apply_all() end
    end
  end
end

-- Retouche locale : k = type ("plo", "de", "lvl"), d = réglage ; k = nil efface les retouches de la zone.
-- Recliquer sur le réglage actif l'enlève.
local function retouch(k, d)
  takes = selected_takes()
  local touched = 0
  for _, e in ipairs(takes) do if sel_zone(e) then touched = touched + 1 end end
  if touched == 0 then set_msg("Faites d'abord une sélection temporelle sur un item sélectionné."); return end
  reaper.Undo_BeginBlock()
  for _, e in ipairs(takes) do
    local a, b = sel_zone(e)
    if a then
      local list, keep, same = get_ret(e.take), {}, false
      for _, r in ipairs(list) do
        local overlap = r.a < b and r.b > a
        if overlap and (k == nil or r.k == k) then
          if r.k == k and r.d == d then same = true end
        else keep[#keep + 1] = r end
      end
      if k and not same then keep[#keep + 1] = { k = k, a = a, b = b, d = d } end
      set_ret(e.take, keep)
    end
  end
  local all = true
  for _, e in ipairs(takes) do if not cache[take_key(e.item, e.take)] then all = false end end
  if all then apply_all() else start_analysis() end
  reaper.Undo_EndBlock(TITLE .. " : retouche locale", -1)
end

-- état de la retouche dans la zone sélectionnée (pour la première prise concernée)
local function zone_state()
  for _, e in ipairs(takes) do
    local a, b = sel_zone(e)
    if a then
      local st, n = {}, 0
      for _, r in ipairs(get_ret(e.take)) do
        if r.a < b and r.b > a then st[r.k] = r.d; n = n + 1 end
      end
      local s, t = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
      return st, n, s, t
    end
  end
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

-- Bypass : coupe ou rétablit le plugin des items sélectionnés (les courbes et retouches sont conservées)
local function fx_state()
  local all, byp = #takes > 0, false
  for _, e in ipairs(takes) do
    local fx = find_fx(e.take)
    if fx < 0 or not cache[take_key(e.item, e.take)] then all = false
    elseif not reaper.TakeFX_GetEnabled(e.take, fx) then byp = true end
  end
  return all, byp
end

local function toggle_bypass()
  local _, byp = fx_state()
  reaper.Undo_BeginBlock()
  for _, e in ipairs(takes) do
    local fx = find_fx(e.take)
    if fx >= 0 then reaper.TakeFX_SetEnabled(e.take, fx, byp) end
  end
  reaper.Undo_EndBlock(TITLE .. (byp and " : traitement réactivé" or " : bypass"), -1)
  reaper.UpdateArrange()
  set_msg(byp and "Traitement réactivé." or "Bypass : vous entendez le son d'origine. Recliquez sur « Bypass » pour réentendre le traitement.")
end

-- bouton principal : « Analyser et appliquer » tant que la sélection n'est pas traitée, puis « Bypass »
local function main_button(x, y, w, h)
  if job and cancel_job then
    if button("Annuler l'analyse", x, y, w, h, false) then cancel_job() end
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
  local n = #takes
  local analysed = 0
  for _, e in ipairs(takes) do if cache[take_key(e.item, e.take)] then analysed = analysed + 1 end end
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
  if button("Réglages avancés", x + w - 160, by, 160, 36) then resize_to(1); return true end
  if chg and not job then
    local any = false
    for _, e in ipairs(takes) do if cache[take_key(e.item, e.take)] then any = true end end
    if any then apply_all() else save() end
  end
  gfx.update()
  return true
end

local function draw()
  if S.adv ~= 1 then return draw_simple() end
  col(COL.bg); gfx.rect(0, 0, U.W(), U.H(), 1)
  text(TITLE, 22, 16, COL.text, 3)
  local n = #takes
  local analysed = 0
  for _, e in ipairs(takes) do if cache[take_key(e.item, e.take)] then analysed = analysed + 1 end end
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
    takes = selected_takes()
    local k = remove_all(takes)
    UI.stats, UI.eq = nil, nil
    set_msg(k > 0 and string.format("Plugin et courbes retirés de %d item%s.", k, k > 1 and "s" or "") or "Rien à retirer sur la sélection.")
  end
  if button("◂ Vue simple", W - 140, by, 118, 30) then resize_to(0); return true end

  if reanalyse then cache = {}; start_analysis()        -- nouvelle fréquence : il faut réécouter l'audio
  elseif chg and not job then
    local any = false
    for _, e in ipairs(takes) do if cache[take_key(e.item, e.take)] then any = true end end
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
  if job then job() else takes = selected_takes() end
  if not draw() then save(); gfx.quit(); return end
  reaper.defer(loop)
end

if #takes == 0 then
  set_msg("Sélectionnez un ou plusieurs items audio (voix), puis « Analyser et appliquer ».")
else
  start_analysis()
end
reaper.defer(loop)
