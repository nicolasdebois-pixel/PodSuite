-- PodSuite - Transcrire.lua
-- Transcrit les items sélectionnés (une piste par intervenant) avec Whisper, mot par mot,
-- attribue chaque mot à son intervenant et détecte les clics du clicker.
-- Résultat : page « podsuite.html » (interface web de REAPER) + marqueurs de clics.

local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")

---------------------------------------------------------------- Préparation
local proj, projfn, datadir, projname = P.project()
if not projfn then
  reaper.MB("Enregistrez d'abord le projet : PodSuite range ses fichiers à côté de lui.", "PodSuite", 0)
  return
end
if not P.settings_ok() then
  reaper.MB("Indiquez d'abord où se trouvent Whisper et son modèle.", "PodSuite", 0)
  if not P.settings_dialog() then return end
end

local nsel = reaper.CountSelectedMediaItems(0)
if nsel == 0 then
  reaper.MB("Sélectionnez les items à transcrire : un item (ou plusieurs) par intervenant, chacun sur sa piste.", "PodSuite", 0)
  return
end

local tracks, tindex, t0, t1 = {}, {}, math.huge, -math.huge
for i = 0, nsel - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  local tr = reaper.GetMediaItem_Track(it)
  local _, ext = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:PODSUITE", "", false)
  if ext ~= "" then
    reaper.MB("La sélection contient des items d'une piste de montage PodSuite (✂).\nSélectionnez les items des rushes d'origine.", "PodSuite", 0)
    return
  end
  if not tindex[tr] then tindex[tr] = true; tracks[#tracks + 1] = tr end
  local a = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local b = a + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  if a < t0 then t0 = a end
  if b > t1 then t1 = b end
end
table.sort(tracks, function(a, b) return reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER") end)

local datafile = datadir .. P.SEP .. "transcript.json"
if P.exists(datafile) then
  if reaper.MB("Ce projet a déjà une transcription.\nLa remplacer ? Les passages barrés seront perdus.", "PodSuite", 4) ~= 6 then return end
end
reaper.RecursiveCreateDirectory(datadir, 0)

local speakers = {}
for i, tr in ipairs(tracks) do
  local _, name = reaper.GetTrackName(tr)
  local col, hex = reaper.GetTrackColor(tr), nil
  if col ~= 0 then local r, g, b = reaper.ColorFromNative(col); hex = string.format("#%02x%02x%02x", r, g, b) end
  speakers[i] = { name = name, color = hex, guid = reaper.GetTrackGUID(tr) }
end

---------------------------------------------------------------- Étape 1 : analyse audio
-- Passe 1 : énergie par piste (trames de 10 ms) + détection des clics.
-- Passe 2 : écriture des fichiers pour Whisper, SANS les longs silences (Whisper perd des phrases
--           et dérive dans ses minutages après un long silence), et COUPÉS À CHAQUE CLIC : d'un seul
--           tenant, Whisper « nettoie » les reprises et efface la phrase redite après le clic.
--           Une carte par morceau permet de revenir au temps réel.
local function chunk_wav(k) return datadir .. P.SEP .. string.format("whisper_input_%02d.wav", k) end
local function chunk_base(k) return datadir .. P.SEP .. string.format("whisper_%02d", k) end
local logpath = datadir .. P.SEP .. "whisper.log"
local MAXGAP, PAD = 1.0, 0.25            -- silences > 1 s raccourcis, 0,25 s gardés de chaque côté
local DTW_BIAS = 0.20                    -- retard moyen mesuré des minutages DTW

local readers = {}
for i, tr in ipairs(tracks) do readers[i] = P.track_reader(tr) end
local tpl = P.template_load()
local detector = tpl and P.click_detector(t0, tpl, tonumber(P.get("click_sens")) or 50, tonumber(P.get("click_gap")) or 0)
local energy = {}
for i = 1, #tracks do energy[i] = {} end
local BLOCK = P.SR
local total = math.floor((t1 - t0) * P.SR)
local nF = math.ceil(total / 160)
local gain = 1 / math.sqrt(#tracks)
local ui = P.progress("PodSuite — Transcription")
local done = 0
local clicks, chunks, envstr = {}, {}, ""
local db, thr = {}, -60
local start_whisper, wait_whisper, finish, plan, write_pass
local function cleanup_readers() for _, r in ipairs(readers) do r.close() end end

local function read_mix(t, n, with_energy, fbase)
  local mix = {}
  for i = 1, n do mix[i] = 0 end
  for ti, r in ipairs(readers) do
    local s = r.read(t, n)
    local en = energy[ti]
    for i = 1, n do
      local v = s[i]
      mix[i] = mix[i] + v
      if with_energy then local f = fbase + (i - 1) // 160 + 1; en[f] = (en[f] or 0) + v * v end
    end
  end
  for i = 1, n do mix[i] = mix[i] * gain end
  return mix
end

local function analyse()
  local deadline = reaper.time_precise() + 0.05
  while done < total and reaper.time_precise() < deadline do
    local n = math.min(BLOCK, total - done)
    local mix = read_mix(t0 + done / P.SR, n, true, math.floor(done / 160))
    if detector then detector.push(mix, n) end
    done = done + n
  end
  if not ui.draw(0.15 * done / total, string.format("Analyse de l'audio… %d %%", math.floor(100 * done / total))) then
    cleanup_readers(); ui.close(); return
  end
  if done < total then reaper.defer(analyse) return end
  plan()
end

local ENV_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function plan()
  clicks = detector and P.click_events(detector, tonumber(P.get("click_gap")) or 0, tonumber(P.get("click_sens")) or 50) or {}
  local env = {}
  for f = 1, nF do
    local e = 0
    for ti = 1, #tracks do e = e + (energy[ti][f] or 0) end
    local d = 10 * math.log(e / 160 + 1e-12, 10)
    db[f] = d
    local lv = math.floor((d + 80) / 1.25)
    if lv < 0 then lv = 0 elseif lv > 63 then lv = 63 end
    env[f] = ENV_ALPHA:sub(lv + 1, lv + 1)
  end
  envstr = table.concat(env)
  -- les clics ne comptent pas comme de la parole, et chaque clic sépare deux morceaux
  local boundary = {}
  for _, c in ipairs(clicks) do
    local f0, f1 = math.max(1, math.floor((c.t - 0.03 - t0) * 100) + 1), math.min(nF, math.floor((c.e + 0.03 - t0) * 100) + 1)
    for f = f0, f1 do db[f] = -120; boundary[f] = true end
  end
  local sorted = {}
  for f = 1, nF do sorted[f] = db[f] end
  table.sort(sorted)
  local floor = sorted[math.max(1, math.floor(nF * 0.1))] or -90
  thr = math.max(floor + 10, -60)
  local keep = {}
  for f = 1, nF do keep[f] = true end
  local f = 1
  while f <= nF do
    if db[f] <= thr then
      local j = f
      while j <= nF and db[j] <= thr do j = j + 1 end
      if (j - f) * 0.01 > MAXGAP then
        -- on garde plus de marge après la dernière phrase : les fins de phrase sont souvent plus douces
        local a = (f == 1) and 1 or f + math.floor(((j > nF) and 0.8 or PAD) * 100)
        local b = (j > nF) and nF or j - math.floor(PAD * 100) - 1
        for k = a, b do keep[k] = false end
      end
      f = j
    else f = f + 1 end
  end
  for k in pairs(boundary) do keep[k] = false end
  -- morceaux : suites de zones gardées, un nouveau morceau après chaque clic
  local cur, dst, cut = nil, 0, true
  f = 1
  while f <= nF do
    if boundary[f] then cut = true end
    if keep[f] then
      local j = f
      while j <= nF and keep[j] do j = j + 1 end
      if cut or not cur then cur = { segs = {}, len = 0 }; chunks[#chunks + 1] = cur; dst = 0; cut = false end
      cur.segs[#cur.segs + 1] = { src = t0 + (f - 1) * 0.01, dst = dst * 0.01, len = (j - f) * 0.01 }
      dst = dst + (j - f); cur.len = dst * 0.01; f = j
    else f = f + 1 end
  end
  -- un morceau trop court (entre deux clics d'un même code) ne contient pas de parole
  local kept = {}
  for _, c in ipairs(chunks) do if c.len >= 0.4 then kept[#kept + 1] = c end end
  chunks = kept
  if #chunks == 0 then chunks[1] = { segs = { { src = t0, dst = 0, len = t1 - t0 } }, len = t1 - t0 } end
  write_pass()
end

function write_pass()
  local ci, si, off, wav, written, kept = 1, 1, 0, nil, 0, 0
  for _, c in ipairs(chunks) do kept = kept + c.len end
  local function step()
    local deadline = reaper.time_precise() + 0.05
    while ci <= #chunks and reaper.time_precise() < deadline do
      local c = chunks[ci]
      if not wav then
        wav = P.wav_open(chunk_wav(ci))
        if not wav then cleanup_readers(); ui.close(); reaper.MB("Impossible d'écrire dans " .. datadir, "PodSuite", 0) return end
      end
      local m = c.segs[si]
      local nTot = math.floor(m.len * P.SR + 0.5)
      local n = math.min(BLOCK, nTot - off)
      if n > 0 then
        P.wav_write(wav, read_mix(m.src + off / P.SR, n, false), n)
        off = off + n; written = written + n
      end
      if off >= nTot then
        si = si + 1; off = 0
        if si > #c.segs then
          -- 1,5 s de silence à la fin : sans cela, Whisper laisse parfois tomber les derniers mots
          local z = {}
          for i = 1, math.floor(1.5 * P.SR) do z[i] = 0 end
          P.wav_write(wav, z, #z); P.wav_close(wav); wav = nil
          ci = ci + 1; si = 1
        end
      end
    end
    if not ui.draw(0.15 + 0.1 * written / math.max(1, kept * P.SR), "Préparation pour Whisper…") then
      cleanup_readers(); if wav then wav.f:close() end; ui.close(); return
    end
    if ci <= #chunks then reaper.defer(step) return end
    cleanup_readers()
    start_whisper(true)
  end
  step()
end

---------------------------------------------------------------- Étape 2 : Whisper
local function q(s) return '"' .. s .. '"' end
local function dtw_preset(path)
  local f = (path:match("([^/\\]+)$") or path):lower()
  for _, m in ipairs({ { "large%-v3%-turbo", "large.v3.turbo" }, { "large%-v3", "large.v3" }, { "large%-v2", "large.v2" },
      { "large%-v1", "large.v1" }, { "medium%.en", "medium.en" }, { "medium", "medium" }, { "small%.en", "small.en" },
      { "small", "small" }, { "base%.en", "base.en" }, { "base", "base" }, { "tiny%.en", "tiny.en" }, { "tiny", "tiny" } }) do
    if f:find(m[1]) then return m[2] end
  end
end
local started, use_dtw

function start_whisper(try_dtw)
  os.remove(logpath)
  use_dtw = try_dtw and dtw_preset(P.get("model")) or nil
  local args = { q(P.get("whisper")), "-m", q(P.get("model")), "-l", P.get("lang"), "-t", P.get("threads"), "-ojf", "-pp" }
  for k = 1, #chunks do
    os.remove(chunk_base(k) .. ".json")
    args[#args + 1] = "-f"; args[#args + 1] = q(chunk_wav(k))
    args[#args + 1] = "-of"; args[#args + 1] = q(chunk_base(k))
  end
  if use_dtw then args[#args + 1] = "-dtw"; args[#args + 1] = use_dtw; args[#args + 1] = "-nfa" end
  local prompt = P.get("prompt"):gsub('"', "")
  if prompt ~= "" then args[#args + 1] = "--prompt"; args[#args + 1] = q(prompt) end
  local cmd = table.concat(args, " ") .. " > " .. q(logpath) .. " 2>&1"
  if P.WIN then cmd = 'cmd.exe /C "' .. cmd .. '"'
  else cmd = "/bin/sh -c '" .. cmd:gsub("'", "'\\''") .. "'" end
  reaper.ExecProcess(cmd, -1)
  started = started or reaper.time_precise()
  wait_whisper()
end

local last_size, last_change = -1, 0
function wait_whisper()
  local log = P.read_file(logpath) or ""
  local pct = 0
  for v in log:gmatch("progress =%s*(%d+)%%") do pct = tonumber(v) end
  local nd = 0
  for _ in log:gmatch("output_json: saving") do nd = nd + 1 end
  if nd >= #chunks then pct = 100 end
  local frac = math.min(1, (nd + (nd < #chunks and pct / 100 or 0)) / #chunks)
  local now = reaper.time_precise()
  if #log ~= last_size then last_size = #log; last_change = now end
  local elapsed = math.floor(now - started)
  local line = string.format("Transcription Whisper… %d %%   (%d min %02d s)", math.floor(frac * 100), elapsed // 60, elapsed % 60)
  if not ui.draw(0.25 + 0.72 * frac, line) then ui.close(); return end

  if log:find("total time") and P.exists(chunk_base(#chunks) .. ".json") then finish() return end
  local failed = log:find("error:") or log:find("failed to") or log:find("not recognized") or log:find("No such file")
  if (failed and now - last_change > 3) or (now - last_change > 30 and #log == 0) or now - last_change > 300 then
    if use_dtw then last_size = -1; start_whisper(false) return end   -- nouvel essai sans DTW
    ui.close()
    local tail = log:sub(-900)
    reaper.MB("Whisper n'a pas pu terminer.\n\nVérifiez les réglages (PodSuite - Reglages).\n\nDernières lignes du journal :\n" .. (tail ~= "" and tail or "(vide : le programme n'a pas démarré)"), "PodSuite", 0)
    return
  end
  reaper.defer(wait_whisper)
end

---------------------------------------------------------------- Étape 3 : assemblage
local function to_src(map, t)
  local lo, hi = 1, #map
  while lo < hi do local m = (lo + hi + 1) // 2; if map[m].dst <= t then lo = m else hi = m - 1 end end
  local m = map[lo]
  return m.src + math.min(math.max(0, t - m.dst), m.len)
end

local function speaker_of(a, b)
  if #tracks == 1 then return 1 end
  local f0, f1 = math.floor((a - t0) * 100) + 1, math.floor((b - t0) * 100) + 1
  if f1 < f0 then f1 = f0 end
  local best, bi = -1, 1
  for i = 1, #tracks do
    local en, sum = energy[i], 0
    for f = f0, f1 do sum = sum + (en[f] or 0) end
    if sum > best then best = sum; bi = i end
  end
  return bi
end

local function noise_word(w) return w:match("^%[.*%]$") or w:match("^%(.*%)$") or w:match("^%*.*%*$") or w:match("^♪") end

function finish()
  ui.draw(0.98, "Assemblage de la transcription…")
  local raw = {}
  for k, chunk in ipairs(chunks) do
  local ok, res = pcall(P.json_decode, P.read_file(chunk_base(k) .. ".json") or "")
  if not ok or type(res) ~= "table" or type(res.transcription) ~= "table" then
    ui.close(); reaper.MB("Le fichier produit par Whisper est illisible (morceau " .. k .. ").\n" .. tostring(res), "PodSuite", 0); return
  end
  for _, seg in ipairs(res.transcription) do
    local so = seg.offsets or {}
    local cur = nil
    for _, tk in ipairs(seg.tokens or {}) do
      local tx = tk.text or ""
      if tx ~= "" and not tx:match("^%[_") and not tx:match("^<|") then
        local to = tk.offsets or {}
        local ts
        if use_dtw and tk.t_dtw and tk.t_dtw >= 0 then ts = tk.t_dtw / 100 - DTW_BIAS
        else ts = (to.from or so.from or 0) / 1000 end
        local te = (to.to or so.to or 0) / 1000
        if tx:sub(1, 1) == " " or not cur then
          -- un mot qui commence dans le silence ajouté en fin de morceau est une invention de Whisper (« Merci. »)
          if ts >= chunk.len - 0.05 then cur = { skip = true }
          else
            cur = { w = tx:match("^%s*(.-)$"), a = to_src(chunk.segs, math.max(0, ts)), b = to_src(chunk.segs, math.max(0, te)) }
            raw[#raw + 1] = cur
          end
        elseif not cur.skip then
          cur.w = cur.w .. tx; cur.b = to_src(chunk.segs, math.max(0, te))
        end
      end
    end
  end
  end
  table.sort(raw, function(x, y) return x.a < y.a end)
  local words = {}
  for _, r in ipairs(raw) do
    local w = r.w:match("^%s*(.-)%s*$")
    local prev = words[#words]
    if w == "" or noise_word(w) then
      -- ignoré
    elseif prev and (w:match("^[%p]+$") or prev.w:match("'$") or prev.w:match("\226\128\153$")) then
      prev.w = prev.w .. w; prev.b = math.max(prev.b, r.b)
    else
      words[#words + 1] = { w = w, a = r.a, b = r.b }
    end
  end
  -- minutages cohérents
  for i, w in ipairs(words) do
    if i > 1 and w.a < words[i - 1].a + 0.02 then w.a = words[i - 1].a + 0.02 end
  end
  -- fin de mot : début du mot suivant, ou fin réelle de la parole (150 ms sous le seuil) s'il y a une pause
  local function frame(t) return math.floor((t - t0) * 100) + 1 end
  for i, w in ipairs(words) do
    local nx = words[i + 1]
    local cap = math.min(nx and nx.a or t1, w.a + 1.5)
    local b = cap
    for f = frame(w.a) + 6, frame(cap) - 1 do
      local quiet = true
      for k = f, f + 14 do if (db[k] or -120) > thr then quiet = false; break end end
      if quiet then b = t0 + (f - 1) * 0.01 + 0.03; break end
    end
    w.b = math.min(b, cap)
    if w.b < w.a + 0.06 then w.b = math.min(w.a + 0.06, nx and nx.a or w.a + 0.06) end
    w.a = math.floor(w.a * 1000 + 0.5) / 1000; w.b = math.floor(w.b * 1000 + 0.5) / 1000
    w.s = speaker_of(w.a, w.b)
  end

  local data = {
    format = 2, project = projname, created = os.date("%Y-%m-%d %H:%M"),
    start = t0, stop = t1, speakers = speakers, words = words, clicks = clicks,
    calibrated = tpl ~= nil, dtw = use_dtw ~= nil, env = envstr, envstart = t0,
    edits = { strikes = {}, ignored = {} },
  }
  P.publish(data, datafile)
  reaper.SetExtState(P.SECTION, "project", projfn, false)

  reaper.Undo_BeginBlock()
  local i = reaper.CountProjectMarkers(0) - 1
  while i >= 0 do
    local _, isrgn, _, _, name, idx = reaper.EnumProjectMarkers(i)
    if not isrgn and name:sub(1, 4) == "PS: " then reaper.DeleteProjectMarker(0, idx, false) end
    i = i - 1
  end
  local labels = { "PS: clic", "PS: à réécouter", "PS: paragraphe" }
  local colors = { reaper.ColorToNative(255, 69, 58), reaper.ColorToNative(255, 159, 10), reaper.ColorToNative(255, 69, 58) }
  for _, c in ipairs(clicks) do
    reaper.AddProjectMarker2(0, false, c.t, 0, labels[c.n], -1, colors[c.n] | 0x1000000)
  end
  reaper.Undo_EndBlock("PodSuite : marqueurs de clics", -1)

  ui.close()
  reaper.MB(string.format("Transcription terminée : %d mots, %d clic(s)%s.\n\nOuvrez la page de dérushage :\n" .. P.web_url() .. "\n\n(Le script PodSuite - Serveur doit tourner : c'est lui qui applique le montage dans REAPER.)",
    #words, #clicks, tpl and "" or " (clicker non calibré : lancez PodSuite - Calibrer le clicker pour activer la détection)"), "PodSuite", 0)
end

P.install_page()
analyse()
