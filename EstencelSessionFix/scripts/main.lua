--[[
  EstencelSessionFix v0.2 (UE4SS Lua Mod / ホスト側のみ必須)

  直すもの:
    1. 再ロード(全滅・焚き火・NG+など)後、3人目以降が "Registration is closed" で Kick される不具合
       原因: キャラ数がNに達した時点で受付を締め切り、その後に届いた「到着通知」を無条件で Kick していた
       対策: 再ロード中はゲーム側の自動締め切りを止め、Mod が「到着通知がN人分届いた時点」で締め切る
    2. 戻れない人がいると永遠に開始しない問題 → タイムアウト + ホストの強制開始(OK 2回押し / F8)
    3. Kick された人が自動再参加してくる際の一時キャラで、次回待つ人数(N)が狂う問題

  注意: UE4SS では BP 関数のフックは「関数の実行後」にしか呼ばれない(第3引数は無効)。
        そのため本 Mod はすべて「実行後フック」で組んでいる。

  対象: /Game/Mannequins/chel/chelTPC.chelTPC_C, GameInstance_SavingSystem_C
]]

local UEHelpers = require("UEHelpers")

------------------------------------------------------------
-- 設定
------------------------------------------------------------
local CFG = {
  T_CLOSE      = 60,    -- 再ロード開始からこの秒数で、受付を自動で締め切る
  T_START      = 120,   -- 再ロード開始からこの秒数で、自動で強制開始する
  OK_WINDOW    = 3,     -- OK の 2 回押しとみなす間隔(秒)
  KICK_WAIT_MS = 2000,  -- Kick 後、人数を数え直すまでの待ち時間(ミリ秒)
  FORCE_KEY    = Key.F8,
}

local MSG = {
  wait   = "[Mod] 全員の読み込みを待っています。OKを2回押す(またはF8)で強制開始できます",
  close  = "[Mod] まもなく受付を自動で締め切ります",
  start  = "[Mod] まもなく自動で強制開始します(読み込みが終わっていない人はKickされます)",
  again  = "[Mod] もう一度OKを押すと強制開始します(読み込みが終わっていない人はKickされます)",
  forced = "[Mod] 強制開始しました。Kickされた人はメニューで「戻る」を押して再接続をやめてください",
  kick   = "Loading timeout",
}

------------------------------------------------------------
-- 共通
------------------------------------------------------------
local CHEL     = "/Game/Mannequins/chel/chelTPC.chelTPC_C"
local GI_CLASS = "GameInstance_SavingSystem_C"
local SENTINEL = -1   -- ゲーム側の自動締め切りを止めるための値

local KSL, ASL
local function libs()
  if not (KSL and KSL:IsValid()) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
  if not (ASL and ASL:IsValid()) then ASL = StaticFindObject("/Script/AdvancedSessions.Default__AdvancedSessionsLibrary") end
end

local function log(s) print("[SessionFix] " .. s .. "\n") end

local function gi()
  local g = FindFirstOf(GI_CLASS)
  if g and g:IsValid() then return g end
end

local function hostPawn()
  local p = UEHelpers.GetPlayer()
  if p and p:IsValid() then return p end
end

local function same(a, b) return a and b and a:GetAddress() == b:GetAddress() end

local function isServer(o)
  libs()
  return o and o:IsValid() and KSL:IsServer(o)
end

-- ホストがマルチプレイの読み込み待ち中か(ゲーム開始前)
local function loading(h)
  return h and h:IsValid() and h.IsLoadingForMultiplayer and not h.IsLevelLoading_not
end

local function players()
  local t = {}
  for _, c in ipairs(FindAllOf("chelTPC_C") or {}) do
    if c:IsValid() and c.IsPlayerCharacter then t[#t + 1] = c end
  end
  return t
end

local function allLoaded()
  for _, c in ipairs(players()) do
    if not c.IsLoadingCompleted then return false end
  end
  return true
end

-- 読み込み画面に案内を表示(固定欄 Log_Left → だめなら通常のログ欄)
local function showGuide(h, msg)
  local ok = pcall(function()
    local w = h.CurrentWidget
    if w:IsValid() and w.Log_Left:IsValid() then
      w.Log_Left:SetText(FText(msg))
    else
      error("no Log_Left")
    end
  end)
  if not ok then pcall(function() h:AddToLog(msg) end) end
  log("guide: " .. msg)
end

------------------------------------------------------------
-- 再ロード中の状態
------------------------------------------------------------
local N = nil            -- 待つ人数(再ロード前の人数)
local arrived = {}       -- 到着通知が届いたキャラ(アドレス)
local startAt = nil
local warnedClose, warnedStart, stableTicks = false, false, 0
local lastOk = 0

local function restoreN()
  local g = gi()
  if g and N and g.CountCurrentPlayersInSessionAfterLoading == SENTINEL then
    g.CountCurrentPlayersInSessionAfterLoading = N
  end
end

local function resetState()
  restoreN()
  N, arrived, startAt = nil, {}, nil
  warnedClose, warnedStart, stableTicks = false, false, 0
end

local function closeNow(h, why)
  restoreN()
  if not h.IsRegistrationClosed then
    log("close: " .. why)
    h:CountNumOfMultiplayerPlayers()
    h:CloseRegistration_server()
  end
end

------------------------------------------------------------
-- 1. 再ロード開始(ホスト自身の LoadLevels の実行後)
------------------------------------------------------------
local function onLoadLevels(self)
  local h, g = hostPawn(), gi()
  if not (h and g) or startAt then return end
  if not (same(self:get(), h) and isServer(h) and g.EnableMultiplayer and not g.IsFirstTimeInSession) then return end

  local cur = g.CountCurrentPlayersInSessionAfterLoading
  if cur == SENTINEL then return end
  N = cur
  arrived = { [h:GetAddress()] = true }
  startAt = os.time()
  g.CountCurrentPlayersInSessionAfterLoading = SENTINEL   -- ゲーム側の早すぎる締め切りを止める
  log(("reload started: waiting for %d players"):format(N))

  ExecuteWithDelay(1500, function()          -- 読み込み画面ができてから表示
    ExecuteInGameThread(function()
      local h2 = hostPawn()
      if loading(h2) then showGuide(h2, MSG.wait) end
    end)
  end)
end

------------------------------------------------------------
-- 2. 到着通知の後(RequestArriving_serverMain の実行後)
--    N人分の到着がそろったら、Mod が締め切る
------------------------------------------------------------
local function onArriving(self, owner)
  local host = self:get()
  if not (N and host:IsValid() and loading(host)) then return end
  pcall(function()
    local p = owner:get()
    if p:IsValid() then arrived[p:GetAddress()] = true end
  end)
  local n = 0
  for _, c in ipairs(players()) do
    if arrived[c:GetAddress()] then n = n + 1 end
  end
  log(("arrived %d / %d"):format(n, N))
  if n >= N then closeNow(host, "all arrived") end
end

------------------------------------------------------------
-- 3. 強制開始・タイムアウト
------------------------------------------------------------
local function forceStart(why)
  local h = hostPawn()
  if not (loading(h) and isServer(h)) then return end
  log("forceStart: " .. why)
  startAt = nil
  closeNow(h, "force")
  libs()
  for _, c in ipairs(players()) do
    if not same(c, h) and not c.IsLoadingCompleted and c.Controller:IsValid() then
      local ok, err = pcall(function() ASL:KickPlayer(h, c.Controller, FText(MSG.kick)) end)
      log("kick straggler: " .. tostring(ok) .. " " .. tostring(err or ""))
    end
  end
  ExecuteWithDelay(CFG.KICK_WAIT_MS, function()
    ExecuteInGameThread(function()
      local h2 = hostPawn()
      if not loading(h2) then return end
      h2:CountNumOfMultiplayerPlayers()
      if allLoaded() then
        showGuide(h2, MSG.forced)
        h2:StartGameWhenLevelIsLoadedInMultiplayer()
        log("started (force)")
      else
        log("not all loaded yet; waiting")
      end
    end)
  end)
end

LoopAsync(1000, function()
  if N then
    ExecuteInGameThread(function()
      if not N then return end
      local h = hostPawn()
      if not loading(h) then
        log("reload finished")
        resetState()
        return
      end

      -- 締め切り済みで全員読み込み完了なのに始まらない場合の保険(2秒続いたら開始)
      if h.IsRegistrationClosed and allLoaded() then
        stableTicks = stableTicks + 1
        if stableTicks >= 2 then
          log("all loaded but not started -> start")
          h:CountNumOfMultiplayerPlayers()
          h:StartGameWhenLevelIsLoadedInMultiplayer()
          stableTicks = 0
        end
      else
        stableTicks = 0
      end

      if not startAt then return end
      local t = os.time() - startAt
      if t >= CFG.T_START then
        forceStart("timeout")
      elseif t >= CFG.T_START - 10 and not warnedStart then
        warnedStart = true
        showGuide(h, MSG.start)
      elseif t >= CFG.T_CLOSE and not h.IsRegistrationClosed then
        closeNow(h, "timeout")
      elseif t >= CFG.T_CLOSE - 10 and not warnedClose and not h.IsRegistrationClosed then
        warnedClose = true
        showGuide(h, MSG.close)
      end
    end)
  end
  return false
end)

-- OK ボタンの実行後(1回目はゲーム本来の処理で受付が締め切られる)
local function onOk(self)
  local h = hostPawn()
  if not (h and same(self:get(), h) and loading(h) and isServer(h)) then return end
  if h.IsDisabledDuringNotFirstSession or not h.IsRegistrationClosed then return end
  restoreN()
  if os.time() - lastOk <= CFG.OK_WINDOW then
    lastOk = 0
    forceStart("OK x2")
  else
    lastOk = os.time()
    showGuide(h, MSG.again)
  end
end

RegisterKeyBind(CFG.FORCE_KEY, function()
  ExecuteInGameThread(function() forceStart("key") end)
end)

------------------------------------------------------------
-- 4. 次回待つ人数(N)の補正:読み込み完了済みのキャラだけを数える
------------------------------------------------------------
local function onUpdateSaving(self)
  local h, g = hostPawn(), gi()
  if not (h and g) or loading(h) or not isServer(h) then return end
  local n = 0
  for _, c in ipairs(players()) do
    if c.IsLoadingCompleted then n = n + 1 end
  end
  if n > 0 then
    g.CountCurrentPlayersInSessionAfterLoading = n
    log("expected players = " .. n)
  end
end

------------------------------------------------------------
-- フック登録(chelTPC が読み込まれた時点で1回だけ)
-- BP 関数のフックは「実行後」に呼ばれる
------------------------------------------------------------
local hooked = false

NotifyOnNewObject(CHEL, function()
  if hooked then return end
  hooked = true
  ExecuteInGameThread(function()
    local function hook(fn, cb)
      local ok, err = pcall(RegisterHook, CHEL .. ":" .. fn, cb)
      log(("hook %s: %s %s"):format(fn, tostring(ok), tostring(err or "")))
    end
    hook("LoadLevels", onLoadLevels)
    hook("RequestArriving_serverMain", onArriving)
    hook("InpActEvt_OK_K2Node_InputActionEvent_15", onOk)
    hook("UpdateSavingMaxNumOfPlayers", onUpdateSaving)
  end)
end)

log("loaded v0.2")
