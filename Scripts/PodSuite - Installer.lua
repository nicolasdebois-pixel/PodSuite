-- PodSuite - Installer.lua — « PodSuite - Installer »
-- À lancer une fois après l'installation par ReaPack (et à relancer sans risque à tout moment).
-- Installe Whisper et un modèle, enregistre les réglages, aide à activer l'interface web, puis teste tout.
local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])")
local P = dofile(dir .. "PodSuite_lib.lua")

local TITLE = "PodSuite — Installation"
local RES = P.RES
local HF = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
local WIN_ZIP = "https://github.com/ggml-org/whisper.cpp/releases/latest/download/whisper-bin-x64.zip"
local VCREDIST = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
local BREW_INSTALL = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
local MODELS = {
  { name = "Précis", file = "ggml-large-v3-turbo-q5_0.bin", mb = 547, note = "Mac Apple Silicon, PC récent" },
  { name = "Équilibré", file = "ggml-small.bin", mb = 466, note = "PC moyen" },
  { name = "Léger", file = "ggml-base.bin", mb = 141, note = "vieux PC, essais rapides" },
}

---------------------------------------------------------------- Étapes affichées
local steps = {
  { id = "files", label = "Fichiers PodSuite" },
  { id = "whisper", label = "Whisper" },
  { id = "model", label = "Modèle de transcription" },
  { id = "settings", label = "Réglages" },
  { id = "web", label = "Interface web de REAPER" },
  { id = "test", label = "Test de transcription" },
}
local S = {}
for _, s in ipairs(steps) do s.state = "todo"; s.info = ""; S[s.id] = s end
local status_line, progress = "", nil
local function set(id, state, info) S[id].state = state; S[id].info = info or S[id].info end

---------------------------------------------------------------- Fenêtre
local W, H = 600, 330
gfx.init(TITLE, W, H)
local function draw()
  gfx.set(0.1, 0.105, 0.12); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 20, string.byte("b")); gfx.set(0.95, 0.95, 0.95)
  gfx.x, gfx.y = 24, 18; gfx.drawstr("Installation de PodSuite")
  gfx.setfont(2, "Arial", 15)
  local y = 60
  for _, s in ipairs(steps) do
    local icon, r, g, b = "○", 0.5, 0.52, 0.56
    if s.state == "doing" then icon, r, g, b = "●", 0.98, 0.6, 0.2
    elseif s.state == "ok" then icon, r, g, b = "✓", 0.25, 0.8, 0.45
    elseif s.state == "warn" then icon, r, g, b = "!", 1, 0.75, 0.25
    elseif s.state == "fail" then icon, r, g, b = "✕", 1, 0.4, 0.35 end
    gfx.set(r, g, b); gfx.x, gfx.y = 26, y; gfx.drawstr(icon)
    gfx.set(0.92, 0.92, 0.92); gfx.x, gfx.y = 50, y; gfx.drawstr(s.label)
    gfx.set(0.6, 0.62, 0.66); gfx.x, gfx.y = 250, y; gfx.drawstr(s.info)
    y = y + 28
  end
  gfx.set(0.85, 0.85, 0.85); gfx.x, gfx.y = 24, H - 62; gfx.drawstr(status_line)
  if progress then
    gfx.set(0.22, 0.23, 0.26); gfx.rect(24, H - 34, gfx.w - 48, 10, 1)
    gfx.set(0.98, 0.6, 0.2); gfx.rect(24, H - 34, math.floor((gfx.w - 48) * math.max(0, math.min(1, progress))), 10, 1)
  end
  gfx.update()
end

---------------------------------------------------------------- Outils
local function y() coroutine.yield() end
local function q(s) return '"' .. s .. '"' end
local function file_size(p) local f = io.open(p, "rb"); if not f then return 0 end local n = f:seek("end"); f:close(); return n end

local function exec_sync(cmd, ms)
  if P.WIN then cmd = 'cmd.exe /C "' .. cmd .. '"' end
  local r = reaper.ExecProcess(cmd, ms or 5000) or ""
  local code, out = r:match("^(%-?%d+)\n?(.*)$")
  return tonumber(code), out or ""
end

-- Lance une suite de commandes en arrière-plan ; renvoie true/false à la fin, en cédant la main à REAPER.
local function run_bg(cmds, log, on_wait)
  local st = log .. ".status"
  os.remove(st); os.remove(log)
  local chain = table.concat(cmds, " && ")
  local full
  if P.WIN then
    full = 'cmd.exe /C "(' .. chain .. ') > ' .. q(log) .. ' 2>&1 && (echo ok>' .. q(st) .. ') || (echo fail>' .. q(st) .. ')"'
  else
    local sh = "( " .. chain .. " ) > " .. q(log) .. " 2>&1; if [ $? -eq 0 ]; then echo ok > " .. q(st) .. "; else echo fail > " .. q(st) .. "; fi"
    full = "/bin/sh -c '" .. sh:gsub("'", "'\\''") .. "'"
  end
  reaper.ExecProcess(full, -1)
  local t0 = reaper.time_precise()
  while true do
    local r = P.read_file(st)
    if r and r:find("ok") then return true end
    if r and r:find("fail") then return false end
    if on_wait then on_wait(reaper.time_precise() - t0) end
    y()
  end
end

local function tail(p, n) local s = P.read_file(p) or ""; return s:sub(-(n or 600)) end
local function mmss(t) t = math.floor(t); return string.format("%d min %02d s", t // 60, t % 60) end

local function find_file(root, name, depth)
  depth = depth or 0
  if depth > 4 then return nil end
  reaper.EnumerateFiles(root, -1)
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(root, i); if not f then break end
    if f:lower() == name:lower() then return root .. P.SEP .. f end
    i = i + 1
  end
  i = 0
  while true do
    local d = reaper.EnumerateSubdirectories(root, i); if not d then break end
    local r = find_file(root .. P.SEP .. d, name, depth + 1); if r then return r end
    i = i + 1
  end
end

local function is_model(p)
  local f = io.open(p, "rb"); if not f then return false end
  local m = f:read(4); local n = f:seek("end"); f:close()
  return m == "lmgg" and n > 30e6
end

local function clipboard(s) if reaper.CF_SetClipboard then reaper.CF_SetClipboard(s); return true end return false end
local function abort(msg) status_line = msg; progress = nil; draw(); error("__abort__") end

---------------------------------------------------------------- Étape 1 : fichiers
local function step_files()
  set("files", "doing")
  reaper.RecursiveCreateDirectory(RES, 0)
  if P.install_page() then set("files", "ok", "version " .. P.VERSION)
  else set("files", "fail", "page introuvable"); abort("Le fichier podsuite.html manque : réinstallez PodSuite depuis ReaPack.") end
end

---------------------------------------------------------------- Étape 2 : Whisper
local function step_whisper()
  set("whisper", "doing", "recherche…"); y()
  if P.exists(P.get("whisper")) then set("whisper", "ok", "déjà installé"); return end

  if not P.WIN then
    local found
    for _, p in ipairs({ "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli" }) do if P.exists(p) then found = p end end
    if not found then
      local brew
      for _, p in ipairs({ "/opt/homebrew/bin/brew", "/usr/local/bin/brew" }) do if P.exists(p) then brew = p end end
      if not brew then
        set("whisper", "fail", "Homebrew nécessaire")
        local copied = clipboard(BREW_INSTALL)
        reaper.MB("Sur Mac, Whisper s'installe avec Homebrew, qui n'est pas encore présent.\n\n" ..
          "1. Ouvrez l'application Terminal.\n2. Collez cette commande" .. (copied and " (elle est déjà copiée)" or "") .. " puis Entrée :\n\n" ..
          BREW_INSTALL .. "\n\n3. Suivez les instructions (mot de passe du Mac demandé).\n4. Relancez « PodSuite - Installer ».", TITLE, 0)
        abort("Installez Homebrew puis relancez l'installation.")
      end
      if reaper.MB("Whisper va être installé avec Homebrew.\nCela prend quelques minutes, REAPER reste utilisable.\n\nContinuer ?", TITLE, 1) ~= 1 then abort("Installation annulée.") end
      set("whisper", "doing", "installation (Homebrew)…")
      local log = RES .. "/brew.log"
      local ok = run_bg({ "export HOMEBREW_NO_AUTO_UPDATE=1", q(brew) .. " install whisper-cpp" }, log,
        function(t) status_line = "Installation de Whisper avec Homebrew… " .. mmss(t); progress = nil end)
      for _, p in ipairs({ "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli" }) do if P.exists(p) then found = p end end
      if not ok or not found then
        set("whisper", "fail", "échec Homebrew")
        reaper.MB("Homebrew n'a pas pu installer Whisper.\n\nJournal :\n" .. tail(log), TITLE, 0)
        abort("Échec de l'installation de Whisper.")
      end
    end
    P.set("whisper", found); set("whisper", "ok", found); return
  end

  -- Windows : version officielle de whisper.cpp
  local dest = RES .. "\\whisper"
  local found = find_file(dest, "whisper-cli.exe")
  if not found then
    reaper.RecursiveCreateDirectory(dest, 0)
    set("whisper", "doing", "téléchargement…")
    local zip = RES .. "\\whisper.zip"
    local log = RES .. "\\whisper_dl.log"
    local ok = run_bg({ "curl.exe -L --fail -sS -o " .. q(zip) .. " " .. q(WIN_ZIP), "tar.exe -xf " .. q(zip) .. " -C " .. q(dest) }, log,
      function(t) local mb = file_size(zip) / 1048576; status_line = string.format("Téléchargement de Whisper… %.1f Mo", mb); progress = math.min(0.95, mb / 8) end)
    progress = nil
    os.remove(zip)
    found = find_file(dest, "whisper-cli.exe")
    if not ok or not found then
      set("whisper", "fail", "téléchargement impossible")
      reaper.MB("Le téléchargement de Whisper a échoué.\nVérifiez la connexion internet (ou un pare-feu d'école), puis relancez.\n\nJournal :\n" .. tail(log), TITLE, 0)
      abort("Échec du téléchargement de Whisper.")
    end
  end
  P.set("whisper", found); set("whisper", "ok", "installé")
end

---------------------------------------------------------------- Étape 3 : modèle
local function step_model()
  set("model", "doing")
  if is_model(P.get("model")) then set("model", "ok", (P.get("model"):match("([^/\\]+)$"))); return end
  local mdir = RES .. P.SEP .. "models"
  reaper.RecursiveCreateDirectory(mdir, 0)
  -- un modèle déjà téléchargé ?
  for _, m in ipairs(MODELS) do
    local p = mdir .. P.SEP .. m.file
    if is_model(p) then P.set("model", p); set("model", "ok", m.file); return end
  end
  local arm = reaper.GetOS():find("arm64") ~= nil
  local items = {}
  for i, m in ipairs(MODELS) do
    items[i] = string.format("%s%s — %d Mo (%s)", (i == (arm and 1 or 2)) and "!" or "", m.name, m.mb, m.note)
  end
  status_line = "Choisissez le modèle dans le menu."
  draw()
  gfx.x, gfx.y = 250, 60 + 2 * 28
  local choice = gfx.showmenu("#Quel modèle installer ?|" .. table.concat(items, "|"))
  choice = choice - 1                       -- la 1re ligne est un titre
  if choice < 1 or choice > #MODELS then abort("Installation annulée : aucun modèle choisi.") end
  local m = MODELS[choice]
  local dst = mdir .. P.SEP .. m.file
  local part = dst .. ".part"
  local log = mdir .. P.SEP .. "download.log"
  set("model", "doing", m.name .. " · téléchargement…")
  local ok = run_bg({ (P.WIN and "curl.exe" or "/usr/bin/curl") .. " -L --fail -sS -o " .. q(part) .. " " .. q(HF .. m.file) }, log,
    function(t)
      local mb = file_size(part) / 1048576
      progress = mb / m.mb
      status_line = string.format("Téléchargement du modèle %s… %d / %d Mo", m.name, math.floor(mb), m.mb)
    end)
  progress = nil
  if ok then os.remove(dst); os.rename(part, dst) end
  if not ok or not is_model(dst) then
    os.remove(part)
    set("model", "fail", "téléchargement impossible")
    reaper.MB("Le téléchargement du modèle a échoué.\nVérifiez la connexion internet, puis relancez.\n\nJournal :\n" .. tail(log), TITLE, 0)
    abort("Échec du téléchargement du modèle.")
  end
  P.set("model", dst); set("model", "ok", m.file)
end

---------------------------------------------------------------- Étape 4 : réglages
local function step_settings()
  set("settings", "doing")
  local cores
  if P.WIN then
    cores = math.floor((tonumber(os.getenv("NUMBER_OF_PROCESSORS") or "") or 4) / 2)
  else
    local _, out = exec_sync("/usr/sbin/sysctl -n hw.perflevel0.physicalcpu", 3000)
    cores = tonumber(out:match("%d+"))
    if not cores then local _, o2 = exec_sync("/usr/sbin/sysctl -n hw.physicalcpu", 3000); cores = tonumber(o2:match("%d+")) end
  end
  cores = math.max(2, math.min(8, cores or 4))
  if reaper.GetExtState(P.SECTION, "cfg_threads") == "" then P.set("threads", cores) end
  if reaper.GetExtState(P.SECTION, "cfg_lang") == "" then P.set("lang", "fr") end
  set("settings", "ok", string.format("langue %s · %s cœurs", P.get("lang"), P.get("threads")))
end

---------------------------------------------------------------- Étape 5 : interface web
local function port_in_use(port)
  if P.WIN then
    local _, out = exec_sync('netstat -an | findstr /C:":' .. port .. ' "', 5000)
    return out:find("LISTENING") ~= nil or out:find("ÉCOUTE") ~= nil or out:find("ECOUTE") ~= nil
  end
  local _, out = exec_sync("/usr/sbin/lsof -nP -iTCP:" .. port .. " -sTCP:LISTEN", 5000)
  return out:find("LISTEN") ~= nil
end

local function step_web()
  set("web", "doing")
  local port = P.web_port()
  if port then set("web", "ok", "port " .. port); return end
  local free = 8080
  for p = 8080, 8099 do if not port_in_use(p) then free = p; break end end
  reaper.MB("Dernière étape manuelle : activer l'interface web de REAPER (30 secondes).\n\n" ..
    "Les préférences vont s'ouvrir :\n" ..
    "1. Rubrique « Control/OSC/web », bouton « Add ».\n" ..
    "2. Control surface mode : « Web browser interface ».\n" ..
    "3. Port : " .. free .. " (libre sur cet ordinateur).\n" ..
    "4. Laissez le reste tel quel, puis OK, et OK pour fermer les préférences.\n\n" ..
    "L'installation reprend toute seule ensuite.", TITLE, 0)
  reaper.Main_OnCommand(40016, 0)        -- Options › Preferences
  set("web", "doing", "en attente…")
  local t0 = reaper.time_precise()
  while not P.web_port() do
    local t = reaper.time_precise() - t0
    status_line = "En attente de l'interface web… (" .. mmss(t) .. ")"
    if t > 240 then
      set("web", "warn", "à vérifier")
      status_line = ""
      reaper.MB("Je ne vois pas encore l'interface web dans la configuration de REAPER.\n\n" ..
        "Si vous l'avez bien ajoutée, quittez et relancez REAPER, puis relancez cette installation pour vérifier.", TITLE, 0)
      return
    end
    y()
  end
  set("web", "ok", "port " .. P.web_port())
end

---------------------------------------------------------------- Étape 6 : test
local function step_test()
  set("test", "doing", "chargement du modèle…")
  local wav = RES .. P.SEP .. "test.wav"
  local w = P.wav_open(wav)
  local s = {}
  for i = 1, 2 * P.SR do s[i] = math.sin(i * 0.05) * 0.001 end
  P.wav_write(w, s, #s); P.wav_close(w)
  local log = RES .. P.SEP .. "test.log"
  local ok = run_bg({ q(P.get("whisper")) .. " -m " .. q(P.get("model")) .. " -f " .. q(wav) .. " -l " .. P.get("lang") .. " -t " .. P.get("threads") .. " -np" }, log,
    function(t) status_line = "Test de Whisper… " .. mmss(t) end)
  if ok then set("test", "ok", "Whisper fonctionne"); return end
  set("test", "fail", "Whisper ne démarre pas")
  local msg = "Whisper est installé mais ne démarre pas.\n\nJournal :\n" .. tail(log, 500)
  if P.WIN then
    msg = msg .. "\n\nSur Windows, c'est presque toujours un composant Microsoft manquant.\nInstallez « Visual C++ Redistributable » (x64) :\n" .. VCREDIST .. "\npuis relancez cette installation."
    clipboard(VCREDIST)
  end
  reaper.MB(msg, TITLE, 0)
  abort("Le test a échoué.")
end

---------------------------------------------------------------- Déroulement
local function main()
  step_files(); y()
  step_whisper(); y()
  step_model(); y()
  step_settings(); y()
  step_web(); y()
  step_test()
  status_line = "PodSuite est prêt."
  progress = nil
  draw()
  local warn = S.web.state ~= "ok"
  reaper.MB("PodSuite est prêt" .. (warn and " (interface web à vérifier)" or "") .. ".\n\n" ..
    "Pour travailler :\n" ..
    "1. Enregistrez votre projet.\n" ..
    "2. Lancez « PodSuite - Serveur » (laissez-le tourner).\n" ..
    "3. Sélectionnez les items des intervenants, puis « PodSuite - Transcrire ».\n" ..
    "4. Ouvrez la page de dérushage : " .. P.web_url() .. "\n\n" ..
    "Astuce : ajoutez ces actions à une barre d'outils (clic droit sur une barre › Customize toolbar).", TITLE, 0)
  gfx.quit()
end

local co = coroutine.create(main)
local function idle()                              -- après un arrêt : la fenêtre reste lisible jusqu'à sa fermeture
  if gfx.getchar() < 0 then return end
  draw(); reaper.defer(idle)
end
local function tick()
  if gfx.getchar() < 0 then return end           -- fenêtre fermée : on arrête
  local ok, err = coroutine.resume(co)
  if not ok then
    if not tostring(err):find("__abort__") then
      status_line = "Erreur inattendue (détails dans la fenêtre de message)."
      reaper.MB("Erreur inattendue :\n" .. tostring(err), TITLE, 0)
    end
    idle(); return
  end
  if coroutine.status(co) ~= "dead" then draw(); reaper.defer(tick) end
end
draw()
reaper.defer(tick)
