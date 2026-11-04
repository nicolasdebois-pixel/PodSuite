-- Toolbox - Transcrire VO.lua — crée les répliques de doublage à partir de la version originale.
-- Sélectionnez l'item de la VO (dialogues), puis lancez (depuis la page « Répliques »).
-- Whisper écrit chaque réplique et la place exactement sur le temps de parole (piste « @VO »).
-- Traduction au choix : anglais (par Whisper, hors ligne), ou français / italien / espagnol
-- (service gratuit MyMemory, connexion internet nécessaire ; environ 5 000 caractères par jour).
-- Le texte original reste visible en petit sur la bande, pour l'adaptation.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local A = dofile(dir .. "Toolbox_adr.lua")
local P = A.P
local TITLE = "Podcast & ADR Toolbox — Transcrire la VO"
local LANG_NAMES = { fr = "français", en = "anglais", it = "italien", es = "espagnol", de = "allemand", nl = "néerlandais", pt = "portugais" }

local target = A.get("target", "")                 -- "" = garder la langue originale
if not P.settings_ok() then
  reaper.MB("La transcription n'est pas encore installée.\n\nFenêtre principale › Accueil › Installer / réparer.", TITLE, 0)
  return
end
local it = reaper.GetSelectedMediaItem(0, 0)
local tk = it and reaper.GetActiveTake(it)
if not tk or reaper.TakeIsMIDI(tk) then
  reaper.MB("Sélectionnez l'item audio de la VO (les dialogues originaux), puis relancez.", TITLE, 0)
  return
end
local item_pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
local item_len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

local work = P.RES .. P.SEP .. "adr"
reaper.RecursiveCreateDirectory(work, 0)
local wav, base, logp = work .. P.SEP .. "vo.wav", work .. P.SEP .. "vo", work .. P.SEP .. "whisper.log"
local function q(s) return '"' .. s .. '"' end
local function shell(cmd)
  if P.WIN then return 'cmd.exe /C "' .. cmd .. '"' end
  return "/bin/sh -c '" .. cmd:gsub("'", "'\\''") .. "'"
end

local ui = P.progress(TITLE)

---------------------------------------------------------------- 1. Audio de la VO en 16 kHz mono
local acc = reaper.CreateTakeAudioAccessor(tk)
local total = math.floor(item_len * P.SR)
local w = P.wav_open(wav)
if not w then ui.close(); reaper.MB("Impossible d'écrire dans " .. work, TITLE, 0); return end
local done, CH = 0, P.SR * 10
local buf = reaper.new_array(CH * 2)
local translated, vo_lang = {}, nil

local start_whisper, wait_whisper, translate_next, finish
local segments = {}

local function read_step()
  local n = math.min(CH, total - done)
  if n <= 0 then
    reaper.DestroyAudioAccessor(acc); P.wav_close(w)
    start_whisper(); return
  end
  buf.clear()
  reaper.GetAudioAccessorSamples(acc, P.SR, 2, done / P.SR, n, buf)
  local s, out = buf.table(), {}
  for i = 1, n do out[i] = (s[2 * i - 1] + s[2 * i]) * 0.5 end
  P.wav_write(w, out, n)
  done = done + n
  if not ui.draw(0.15 * done / total, "Lecture de la VO…") then reaper.DestroyAudioAccessor(acc); P.wav_close(w); ui.close(); return end
  reaper.defer(read_step)
end

---------------------------------------------------------------- 2. Whisper
local t0
function start_whisper()
  os.remove(logp); os.remove(base .. ".json")
  local args = { q(P.get("whisper")), "-m", q(P.get("model")), "-l", "auto", "-t", P.get("threads"), "-oj", "-pp",
    "-ml", "84", "-sow", "-f", q(wav), "-of", q(base) }
  if target == "en" then args[#args + 1] = "-tr" end             -- Whisper traduit lui-même vers l'anglais
  reaper.ExecProcess(shell(table.concat(args, " ") .. " > " .. q(logp) .. " 2>&1"), -1)
  t0 = reaper.time_precise()
  wait_whisper()
end

local last_size, last_change = -1, reaper.time_precise()
function wait_whisper()
  local log = P.read_file(logp) or ""
  local pct = 0
  for v in log:gmatch("progress =%s*(%d+)%%") do pct = tonumber(v) end
  local now = reaper.time_precise()
  if #log ~= last_size then last_size = #log; last_change = now end
  local el = math.floor(now - t0)
  if not ui.draw(0.15 + 0.6 * pct / 100, string.format("Transcription de la VO… %d %%  (%d min %02d s)", pct, el // 60, el % 60)) then ui.close(); return end
  local json = P.read_file(base .. ".json")
  if log:find("total time") and json then
    local ok, data = pcall(P.json_decode, json)
    if not ok or type(data) ~= "table" then ui.close(); reaper.MB("Résultat de Whisper illisible.", TITLE, 0); return end
    vo_lang = data.result and data.result.language
    for _, s in ipairs(data.transcription or {}) do
      local txt = (s.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local a, b = s.offsets and s.offsets.from, s.offsets and s.offsets.to
      if txt ~= "" and a and b and b > a and not txt:match("^%[.*%]$") and not txt:match("^%(.*%)$") then
        segments[#segments + 1] = { pos = item_pos + a / 1000, len = (b - a) / 1000, text = txt }
      end
    end
    translate_next(1); return
  end
  if (log:find("error") and now - last_change > 3) or now - last_change > 300 then
    ui.close(); reaper.MB("Whisper n'a pas pu terminer.\n\n" .. log:sub(-700), TITLE, 0); return
  end
  reaper.defer(wait_whisper)
end

---------------------------------------------------------------- 3. Traduction (MyMemory) ligne par ligne
local tr_state, quota, tr_error = nil, false, nil
local EMAIL, DEEPL = A.get("tr_email", ""), A.get("deepl_key", "")
local function need_mt() return target ~= "" and target ~= "en" and vo_lang and vo_lang ~= target end
function translate_next(k)
  if not need_mt() or quota or k > #segments then finish(); return end
  local seg = segments[k]
  local qf, of = work .. P.SEP .. "q.txt", work .. P.SEP .. "t" .. k .. ".json"
  if not tr_state then
    P.write_file(qf, seg.text)
    os.remove(of)
    local curl = P.WIN and "curl.exe" or "curl"
    local req
    if DEEPL ~= "" then                                    -- DeepL Free : clé personnelle, 500 000 caractères par mois
      local host = DEEPL:find(":fx$") and "https://api-free.deepl.com" or "https://api.deepl.com"
      req = curl .. " -s -m 20 -X POST " .. host .. "/v2/translate -H " .. q("Authorization: DeepL-Auth-Key " .. DEEPL) ..
        " --data-urlencode " .. q("text@" .. qf) .. " --data-urlencode " .. q("target_lang=" .. target:upper())
    else                                                   -- MyMemory : gratuit ; l'e-mail multiplie la limite par 10
      req = curl .. " -s -m 20 -G https://api.mymemory.translated.net/get --data-urlencode " .. q("q@" .. qf) ..
        " --data-urlencode " .. q("langpair=" .. vo_lang .. "|" .. target) .. (EMAIL ~= "" and (" --data-urlencode " .. q("de=" .. EMAIL)) or "")
    end
    reaper.ExecProcess(shell(req .. " -o " .. q(of .. ".part") .. (P.WIN and " && move /Y " or " && mv ") .. q(of .. ".part") .. " " .. q(of)), -1)
    tr_state = reaper.time_precise()
  end
  if not ui.draw(0.75 + 0.25 * k / #segments, string.format("Traduction en %s… %d / %d", LANG_NAMES[target] or target, k, #segments)) then ui.close(); return end
  local res = P.read_file(of)
  if res then
    tr_state = nil
    local ok, d = pcall(P.json_decode, res)
    local t = ok and type(d) == "table" and d.responseData and d.responseData.translatedText
    local status = ok and type(d) == "table" and tonumber(d.responseStatus)
    if ok and type(d) == "table" and type(d.translations) == "table" and d.translations[1] then   -- réponse DeepL
      t, status = d.translations[1].text, 200; d.responseStatus = 200
    elseif ok and type(d) == "table" and type(d.message) == "string" then                      -- erreur DeepL
      if d.message:lower():find("quota") then quota = true else tr_error = d.message end
      t = nil
    end
    if (type(t) == "string" and t:find("MYMEMORY WARNING", 1, true)) or status == 429 or status == 403 then quota = true
    elseif type(t) == "string" and t ~= "" and tonumber(d.responseStatus) == 200 then
      seg.tr = t:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    end
    os.remove(of)
    reaper.defer(function() translate_next(k + 1) end); return
  end
  if reaper.time_precise() - tr_state > 25 then tr_state = nil; reaper.defer(function() translate_next(k + 1) end); return end
  reaper.defer(function() translate_next(k) end)
end

---------------------------------------------------------------- 4. Répliques dans REAPER
function finish()
  ui.close()
  if #segments == 0 then reaper.MB("Whisper n'a trouvé aucune parole dans cet item.", TITLE, 0); return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ntr = 0
  for _, s in ipairs(segments) do
    if s.tr then ntr = ntr + 1; A.add_line("VO", s.pos, s.len, s.tr, s.text)
    else A.add_line("VO", s.pos, s.len, s.text, nil) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Toolbox : répliques depuis la VO", -1)
  local msg = string.format("%d répliques créées sur la piste « @VO »", #segments)
  if target == "en" then msg = msg .. ", traduites en anglais par Whisper"
  elseif need_mt() then
    msg = msg .. string.format(", dont %d traduites en %s", ntr, LANG_NAMES[target] or target)
    if quota then msg = msg .. ".\n\nLa limite gratuite de traduction est atteinte : les autres répliques sont restées en version originale. Dans la page Répliques, « Réglages de traduction » : ajoutez votre e-mail (limite × 10) ou une clé DeepL gratuite" end
    if tr_error then msg = msg .. ".\n\nDeepL a répondu : " .. tr_error .. " (vérifiez la clé dans « Réglages de traduction »)" end
    if ntr == 0 and not quota then msg = msg .. ".\n\nLa traduction n'a pas répondu (connexion internet ?) : les répliques sont en version originale" end
  elseif target ~= "" and vo_lang == target then msg = msg .. " (la VO est déjà en " .. (LANG_NAMES[target] or target) .. ")" end
  reaper.MB(msg .. ".\n\nAttribuez-les ensuite aux personnages : page Répliques, sélectionnez les items puis cliquez sur le personnage.", TITLE, 0)
end

reaper.defer(read_step)
