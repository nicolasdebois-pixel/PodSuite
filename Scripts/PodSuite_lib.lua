-- PodSuite_lib.lua — fonctions communes de la suite PodSuite pour REAPER
-- (ne pas lancer directement : chargé par les autres scripts)

local P = {}
P.VERSION = "0.3.1"
P.SECTION = "PODSUITE"
P.WIN = reaper.GetOS():find("Win") ~= nil
P.SEP = P.WIN and "\\" or "/"
P.SR = 16000                       -- fréquence d'analyse (celle de Whisper)
P.DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])")) or ""
P.RES = reaper.GetResourcePath() .. P.SEP .. "PodSuite"   -- Whisper, modèles, tests

---------------------------------------------------------------- JSON
local escmap = { ['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
local function enc_str(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return escmap[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function enc(v, out)
  local t = type(v)
  if v == nil then out[#out+1] = "null"
  elseif t == "boolean" then out[#out+1] = tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out+1] = "null"
    elseif math.type(v) == "integer" then out[#out+1] = tostring(v)
    else out[#out+1] = (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")) end
  elseif t == "string" then out[#out+1] = enc_str(v)
  elseif t == "table" then
    if next(v) == nil or v[1] ~= nil then
      out[#out+1] = "["
      for i = 1, #v do if i > 1 then out[#out+1] = "," end enc(v[i], out) end
      out[#out+1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys+1] = tostring(k) end
      table.sort(keys)
      out[#out+1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out+1] = "," end
        out[#out+1] = enc_str(k); out[#out+1] = ":"; enc(v[k], out)
      end
      out[#out+1] = "}"
    end
  end
end
function P.json_encode(v) local out = {}; enc(v, out); return table.concat(out) end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
  elseif cp < 0x10000 then return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
  else return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)) end
end

function P.json_decode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local function err(m) error("JSON invalide (" .. m .. ") à la position " .. pos) end
  local val
  local function str()
    pos = pos + 1
    local buf = {}
    while true do
      local a, b = s:find('["\\]', pos)
      if not a then err("chaîne non terminée") end
      buf[#buf+1] = s:sub(pos, a - 1)
      if s:sub(a, a) == '"' then pos = a + 1; break end
      local c = s:sub(a + 1, a + 1)
      if c == "u" then
        local cp = tonumber(s:sub(a + 2, a + 5), 16) or 63
        pos = a + 6
        if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
          local lo = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); pos = pos + 6
        end
        buf[#buf+1] = utf8char(cp)
      else
        buf[#buf+1] = ({ b="\b", f="\f", n="\n", r="\r", t="\t" })[c] or c
        pos = a + 2
      end
    end
    return table.concat(buf)
  end
  function val()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local o = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return o end
      while true do
        ws(); if s:sub(pos, pos) ~= '"' then err("clé attendue") end
        local k = str(); ws()
        if s:sub(pos, pos) ~= ":" then err("':' attendu") end
        pos = pos + 1; o[k] = val(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return o elseif d ~= "," then err("',' ou '}' attendu") end
      end
    elseif c == "[" then
      local a = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return a end
      while true do
        a[#a+1] = val(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return a elseif d ~= "," then err("',' ou ']' attendu") end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then err("valeur inattendue") end
      pos = pos + #num; return tonumber(num)
    end
  end
  return val()
end

---------------------------------------------------------------- Fichiers
function P.read_file(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local d = f:read("a"); f:close(); return d
end
function P.write_file(path, data)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb"); if not f then return false end
  f:write(data); f:close()
  os.remove(path)
  return os.rename(tmp, path)
end
function P.exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb"); if f then f:close(); return true end
  return false
end

function P.project()
  local proj, fn = reaper.EnumProjects(-1)
  if not fn or fn == "" then return proj, nil end
  local dir = fn:match("^(.*)[/\\]")
  local name = fn:match("([^/\\]+)$"):gsub("%.[Rr][Pp][Pp]$", "")
  return proj, fn, dir .. P.SEP .. "PodSuite", name
end

function P.www_dir()
  local d = reaper.GetResourcePath() .. P.SEP .. "reaper_www_root"
  reaper.RecursiveCreateDirectory(d, 0)
  return d
end
function P.www_data() return P.www_dir() .. P.SEP .. "podsuite_data.json" end

-- Copie (ou met à jour) la page de dérushage dans reaper_www_root.
-- ReaPack l'installe à côté des scripts ; dans le zip de développement elle est dans ../www/.
function P.install_page()
  local data = P.read_file(P.DIR .. "podsuite.html") or P.read_file(P.DIR .. ".." .. P.SEP .. "www" .. P.SEP .. "podsuite.html")
  if not data then return false end
  local dst = P.www_dir() .. P.SEP .. "podsuite.html"
  if P.read_file(dst) ~= data then return P.write_file(dst, data) end
  return true
end

-- Port de l'interface web de REAPER (nil si elle n'est pas configurée)
function P.web_port()
  local ini = P.read_file(reaper.get_ini_file()) or ""
  for line in ini:gmatch("[^\r\n]+") do
    local port = line:match("^csurf_%d+=HTTP%s+%S+%s+(%d+)")
    if port and tonumber(port) > 0 and tonumber(port) < 65536 then return tonumber(port) end
  end
end

-- Adresse de la page, avec le port réellement choisi dans Préférences › Control/OSC/web
-- (lu dans reaper.ini, lignes « csurf_N=HTTP flags port … »)
function P.web_url(page)
  page = page or "podsuite.html"
  local port = P.web_port()
  return "http://localhost:" .. (port and tostring(port) or "<votre port>") .. "/" .. page
end

-- Publie les données vers la page web et signale une nouvelle version
function P.publish(data, project_json)
  local js = P.json_encode(data)
  if project_json then P.write_file(project_json, js) end
  P.write_file(P.www_data(), js)
  reaper.SetExtState(P.SECTION, "version", tostring(os.time()) .. "-" .. tostring(math.random(1, 1e6)), false)
end

---------------------------------------------------------------- Réglages
local DEFAULTS = {
  whisper = "", model = "", lang = "fr", threads = "4", prompt = "", extra = "",
  click_sens = "50", click_template = "", click_gap = "0",
}
function P.get(k) local v = reaper.GetExtState(P.SECTION, "cfg_" .. k); if v == "" then return DEFAULTS[k] end return v end
function P.set(k, v) reaper.SetExtState(P.SECTION, "cfg_" .. k, tostring(v), true) end

local function guess_whisper()
  if P.WIN then return "" end
  for _, p in ipairs({ "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cpp", "/usr/local/bin/whisper-cpp" }) do
    if P.exists(p) then return p end
  end
  return ""
end

function P.settings_dialog()
  local w = P.get("whisper"); if not P.exists(w) then w = guess_whisper() end
  local caps = "Programme whisper-cli,Modèle (.bin),Langue (fr, en…),Cœurs CPU,Vocabulaire / noms propres,Sensibilité des clics (0-100),extrawidth=420,separator=\n"
  local vals = table.concat({ w, P.get("model"), P.get("lang"), P.get("threads"), P.get("prompt"), P.get("click_sens") }, "\n")
  local ok, res = reaper.GetUserInputs("PodSuite — Réglages", 6, caps, vals)
  if not ok then return false end
  local f = {}
  for v in (res .. "\n"):gmatch("(.-)\n") do f[#f+1] = v:match("^%s*(.-)%s*$") end
  if not P.exists(f[1]) then
    reaper.MB("Je ne trouve pas whisper-cli.\n\nChoisissez le fichier dans la fenêtre suivante :\n• Mac : /opt/homebrew/bin/whisper-cli\n• Windows : whisper-cli.exe dans le dossier dézippé.", "PodSuite", 0)
    local ok2, p = reaper.GetUserFileNameForRead(f[1], "Choisir whisper-cli", P.WIN and "*.exe" or "")
    if ok2 then f[1] = p end
  end
  if not P.exists(f[2]) then
    reaper.MB("Je ne trouve pas le modèle.\n\nChoisissez le fichier .bin téléchargé (par ex. ggml-large-v3-turbo-q5_0.bin).", "PodSuite", 0)
    local ok2, p = reaper.GetUserFileNameForRead(f[2], "Choisir le modèle Whisper", "*.bin")
    if ok2 then f[2] = p end
  end
  P.set("whisper", f[1]); P.set("model", f[2]); P.set("lang", f[3] ~= "" and f[3] or "fr")
  P.set("threads", tonumber(f[4]) and f[4] or "4"); P.set("prompt", f[5])
  P.set("click_sens", tostring(math.max(0, math.min(100, tonumber(f[6]) or 50))))
  return P.exists(f[1]) and P.exists(f[2])
end

function P.settings_ok() return P.exists(P.get("whisper")) and P.exists(P.get("model")) end

---------------------------------------------------------------- Audio
-- Lecteur mono 16 kHz d'une piste (avant les effets de piste)
function P.track_reader(tr)
  local acc = reaper.CreateTrackAudioAccessor(tr)
  local cache = {}
  return {
    read = function(t, n)
      local buf = cache[n]
      if not buf then buf = reaper.new_array(n * 2); cache[n] = buf end
      buf.clear()
      reaper.GetAudioAccessorSamples(acc, P.SR, 2, t, n, buf)
      local s, out = buf.table(), {}
      for i = 1, n do out[i] = (s[2*i - 1] + s[2*i]) * 0.5 end
      return out
    end,
    close = function() reaper.DestroyAudioAccessor(acc) end,
  }
end

-- Écriture WAV 16 bits mono
function P.wav_open(path)
  local f = io.open(path, "wb"); if not f then return nil end
  f:write(string.rep("\0", 44))
  return { f = f, n = 0 }
end
function P.wav_write(w, s, n)
  local CH = 2048
  for i = 1, n, CH do
    local j = math.min(n, i + CH - 1)
    local t = {}
    for k = i, j do
      local v = s[k]
      if v > 1 then v = 1 elseif v < -1 then v = -1 end
      t[#t+1] = math.floor(v * 32767 + 0.5)
    end
    w.f:write(string.pack("<" .. string.rep("i2", #t), table.unpack(t)))
  end
  w.n = w.n + n
end
function P.wav_close(w)
  local bytes = w.n * 2
  w.f:seek("set", 0)
  w.f:write("RIFF", string.pack("<I4", 36 + bytes), "WAVE", "fmt ",
    string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, P.SR, P.SR * 2, 2, 16), "data", string.pack("<I4", bytes))
  w.f:close()
end

---------------------------------------------------------------- Détecteur de clics (clicker)
-- Travaille en flux sur le signal 16 kHz. Un clic = transitoire bref, aigu, qui retombe vite,
-- confirmé (si calibré) par corrélation avec l'empreinte enregistrée.
local FR = 16          -- trame d'énergie : 1 ms
local LOOK = 24        -- retard d'évaluation : 24 ms
local RING = 32768
local TPL_PRE, TPL_LEN = 32, 192

function P.click_detector(t0, template, sens)
  local D = {
    t0 = t0, n = 0, prev = 0, acc = 0, cnt = 0, k = 0,
    h = {}, E = {}, P = {}, hits = {}, last = -1e9,
    tpl = template, thr = 0.85 - 0.5 * (sens / 100),
  }
  local R1 = 20                        -- montée d'au moins 13 dB au-dessus du fond
  local DEC = 6                        -- retombée de 8 dB en moins de 10 ms
  local FLOOR = FR * 2e-5

  local function ncc(peak)
    local tpl, h = D.tpl, D.h
    local best = 0
    for lag = -24, 24 do
      local base = peak - TPL_PRE + lag
      local dot, en = 0, 0
      for i = 1, TPL_LEN do
        local x = h[(base + i - 1) % RING] or 0
        dot = dot + x * tpl[i]; en = en + x * x
      end
      if en > 0 then
        local c = math.abs(dot) / math.sqrt(en)
        if c > best then best = c end
      end
    end
    return best
  end

  local function evaluate(c)
    local E = D.E
    local ec = E[c % 256]
    if not ec or ec < FLOOR or c < 48 then return end
    for j = c - 3, c + 3 do if j ~= c and (E[j % 256] or 0) > ec then return end end
    local bg = 0
    for j = c - 44, c - 6 do bg = bg + (E[j % 256] or 0) end
    bg = bg / 39 + 1e-9
    if ec < bg * R1 then return end
    local tail = 0
    for j = c + 10, c + LOOK - 2 do local e = E[j % 256] or 0; if e > tail then tail = e end end
    if tail > ec / DEC then return end
    local peak = D.P[c % 256]
    if (peak - D.last) < 0.03 * P.SR then return end
    if ncc(peak) < D.thr then return end
    D.last = peak
    D.hits[#D.hits + 1] = D.t0 + peak / P.SR
  end

  function D.push(s, n)
    local h, E, Pk = D.h, D.E, D.P
    local prev, acc, cnt, k, idx = D.prev, D.acc, D.cnt, D.k, D.n
    local pmax, pidx = D.pmax or 0, D.pidx or 0
    for i = 1, n do
      local x = s[i]
      local d = x - prev; prev = x
      h[idx % RING] = d
      local d2 = d * d
      acc = acc + d2
      if d2 > pmax then pmax = d2; pidx = idx end
      idx = idx + 1; cnt = cnt + 1
      if cnt == FR then
        E[k % 256] = acc; Pk[k % 256] = pidx
        D.k = k; D.n = idx
        evaluate(k - LOOK)
        k = k + 1; acc = 0; cnt = 0; pmax = 0
      end
    end
    D.prev, D.acc, D.cnt, D.k, D.n, D.pmax, D.pidx = prev, acc, cnt, k, idx, pmax, pidx
  end
  return D
end

-- Regroupe les transitoires : appui + relâchement = 1 clic ; clics rapprochés = un code (1, 2, 3)
function P.group_clicks(hits, gap)
  local events = {}
  local win = gap > 0 and math.max(0.08, gap * 1.5 + 0.04) or 0.08
  local maxtr = gap > 0 and 2 or 1
  for _, t in ipairs(hits) do
    local e = events[#events]
    if e and e.n < maxtr and t - e.t <= win then e.n = e.n + 1; e.e = t
    else events[#events + 1] = { t = t, e = t, n = 1 } end
  end
  local codes = {}
  for _, ev in ipairs(events) do
    local c = codes[#codes]
    if c and ev.t - c.e <= 1.2 then c.n = c.n + 1; c.e = ev.e
    else codes[#codes + 1] = { t = ev.t, e = ev.e, n = 1 } end
  end
  for _, c in ipairs(codes) do c.e = c.e + 0.04; if c.n > 3 then c.n = 3 end end
  return codes
end

function P.template_load()
  local s = P.get("click_template")
  if s == "" then return nil end
  local t = {}
  for v in s:gmatch("[^,]+") do t[#t+1] = tonumber(v) end
  if #t ~= TPL_LEN then return nil end
  return t
end

-- Calcule l'empreinte d'un clic à partir d'un signal 16 kHz contenant un clic
function P.template_from(s)
  local h, prev = {}, s[1] or 0
  for i = 1, #s do h[i] = s[i] - prev; prev = s[i] end
  local E, nf = {}, math.floor(#h / FR)
  for f = 0, nf - 1 do local a = 0; for i = f*FR + 1, f*FR + FR do a = a + h[i]*h[i] end; E[f] = a end
  local best, bf = 0, nil
  for f = 0, nf - 1 do if E[f] > best then best = E[f]; bf = f end end
  if not bf or best < FR * 1e-5 then return nil, "aucun clic net dans la sélection" end
  local peak, pm = bf * FR + 1, 0
  for i = bf*FR + 1, bf*FR + FR do if h[i]*h[i] > pm then pm = h[i]*h[i]; peak = i end end
  if peak - TPL_PRE < 1 or peak - TPL_PRE + TPL_LEN - 1 > #h then return nil, "le clic est trop près du bord de la sélection" end
  local tpl, en = {}, 0
  for i = 1, TPL_LEN do local v = h[peak - TPL_PRE + i - 1]; tpl[i] = v; en = en + v*v end
  en = math.sqrt(en)
  for i = 1, TPL_LEN do tpl[i] = tpl[i] / en end
  -- relâchement : second transitoire net, 40 à 600 ms plus tard
  local gap = 0
  local f0, f1 = bf + 40, math.min(nf - 1, bf + 600)
  local b2, g2 = 0, nil
  for f = f0, f1 do if E[f] > b2 then b2 = E[f]; g2 = f end end
  if g2 and b2 > best * 0.04 then gap = (g2 - bf) / 1000 end
  local parts = {}
  for i = 1, TPL_LEN do parts[i] = string.format("%.5f", tpl[i]) end
  return table.concat(parts, ","), gap, peak
end

---------------------------------------------------------------- Fenêtre de progression
function P.progress(title)
  gfx.init(title, 460, 96)
  local W = {}
  function W.draw(frac, line)
    gfx.set(0.09, 0.09, 0.1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
    gfx.setfont(1, "Arial", 16); gfx.set(0.92, 0.92, 0.9)
    gfx.x, gfx.y = 16, 14; gfx.drawstr(line or "")
    gfx.set(0.2, 0.2, 0.23); gfx.rect(16, 48, gfx.w - 32, 14, 1)
    gfx.set(0.94, 0.66, 0.23); gfx.rect(16, 48, math.floor((gfx.w - 32) * math.max(0, math.min(1, frac))), 14, 1)
    gfx.setfont(1, "Arial", 13); gfx.set(0.55, 0.55, 0.6)
    gfx.x, gfx.y = 16, 70; gfx.drawstr("Fermer la fenêtre pour annuler")
    gfx.update()
    return gfx.getchar() >= 0
  end
  function W.close() gfx.quit() end
  return W
end

return P
