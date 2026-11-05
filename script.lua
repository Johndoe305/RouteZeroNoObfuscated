-- Services

--// 1. BYPASS (11x)
for i = 1, 99 do
    for _, func in ipairs(getgc(true)) do
        if type(func) == "function" then
            local ok, info = pcall(debug.getinfo, func)
            if ok and info and info.name == "validityCheck" then
                hookfunction(func, function(Callback, Get, Callback1, p7, ...)
                    return Callback(Get, Callback1, p7, ...)
                end)
                print("hookado (x" .. i .. ")")
                break
            end
        end
    end
    task.wait(0.01)
end
print("Bypass executado")

--// 2. NOTIFICAÇÃO
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Loading...";
    Text = "";
    Icon = "rbxassetid://82285050019288";
    Duration = 7;
})

--// 3. SOM DE CARREGADO
task.spawn(function()
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://3398620867"
    s.Volume = 0.4
    s.Parent = game:GetService("SoundService")
    s:Play()
    task.delay(3, function() s:Destroy() end)
end)

print("[loaded]")

--// 4. ESPERA 9 SEGUNDOS
task.wait(9)

--// 5. GUI COMPLETA
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")
local NetModule = require(ReplicatedStorage.Modules.Core.Network.Net)

--// CORES
local COR_BG     = Color3.fromRGB(15, 15, 25)
local COR_FUNDO  = Color3.fromRGB(10, 10, 20)
local COR_BORDA  = Color3.fromRGB(0, 0, 0)
local COR_TITULO = Color3.fromRGB(200, 220, 255)
local COR_ATTACK = Color3.fromRGB(255, 120, 120)
local COR_ESP    = Color3.fromRGB(255, 60, 60)
local COR_FARM   = Color3.fromRGB(206, 127, 225)

--// CONFIG
local ATRIBUTOS = { "AnomalyPersistent", "AnomalyKind" }
local ATRIBUTO_VIDA = "Health"
local RAIO_ATAQUE = 15          -- ⭐ raio pra atacar
local RAIO_BUSCA = 60          -- ⭐ raio pra buscar
local RAIO_FOLLOW = 3          -- ⭐ follow (se afastar 3, tweena)
local INTERVALO = 0.10
local VELOCIDADE_TWEEN = 0
local TENTATIVAS = 10
local LOOP_WAIT = 0.10

--// STATE
local attackAtivo = false
local espAtivo = false
local farmAtivo = false
local alvoAtual = nil
local tweenAtivo = false
local enviouInicial = false
local highlights = {}
local sendConfirmado = false
local offsetZ = -1

--// HOOK no NetModule
local oldSend = NetModule.send
NetModule.send = function(cmd, ...)
    if cmd == "BatonSwing" or cmd == "BatonHit" then
        sendConfirmado = true
    end
    return oldSend(cmd, ...)
end

--// FUNÇÕES COMUNS
local function temAtributo(obj)
    for _, attr in ipairs(ATRIBUTOS) do
        if obj:GetAttribute(attr) then
            return true, attr
        end
    end
    return false, nil
end

local function alvoVivo(alvo)
    if not alvo or not alvo.Parent then return false end
    local vida = alvo:GetAttribute(ATRIBUTO_VIDA)
    if vida ~= nil then return vida > 0 end
    local hum = alvo:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getVida(alvo)
    if not alvo then return 0 end
    local vida = alvo:GetAttribute(ATRIBUTO_VIDA)
    if vida ~= nil then return vida end
    local hum = alvo:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health or 0
end

local function getBaton()
    local char = player.Character
    if not char then return nil end
    local tool = char:FindFirstChild("Baton")
    if tool then return tool end
    local anyTool = char:FindFirstChildOfClass("Tool")
    if anyTool and anyTool.Name:lower():find("baton") then return anyTool end
    return nil
end

--// AUTO ATTACK
local attackConn
local function iniciarAttack()
    if attackConn then attackConn:Disconnect() end
    attackConn = RunService.Heartbeat:Connect(function()
        if not attackAtivo then return end
        local baton = getBaton()
        if not baton then return end
        pcall(function() baton:Activate() end)
        task.wait(INTERVALO)
    end)
end

local function pararAttack()
    if attackConn then attackConn:Disconnect() attackConn = nil end
end

--// ESP
local function criarHighlight(model)
    if highlights[model] then return end
    local hl = Instance.new("Highlight")
    hl.Name = "ESP_Anomalia"
    hl.FillColor = COR_ESP
    hl.FillTransparency = 0.5
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = model
    hl.Parent = model
    highlights[model] = hl
end

local function removerHighlight(model)
    if highlights[model] then
        highlights[model]:Destroy()
        highlights[model] = nil
    end
end

local function atualizarESP()
    if not espAtivo then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local tem = temAtributo(obj)
            if tem then
                if alvoVivo(obj) then
                    criarHighlight(obj)
                else
                    removerHighlight(obj)
                end
            end
        end
    end
    for model in pairs(highlights) do
        if not model.Parent or not alvoVivo(model) then
            removerHighlight(model)
        end
    end
end

task.spawn(function()
    while true do
        if espAtivo then pcall(atualizarESP) end
        task.wait(0.30)
    end
end)

--// AUTO-FARM (pega o com MAIS VIDA + follow 3)
local function acharAlvo()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, 0 end
    
    local minhaPos = hrp.Position
    
    local melhorAtaque = nil
    local maiorVidaAtaque = 0
    local distAtaque = 0
    local atributoAtaque = nil
    
    local melhorBusca = nil
    local maiorVidaBusca = 0
    local distBusca = 0
    local atributoBusca = nil
    
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local tem, attr = temAtributo(obj)
            if tem and alvoVivo(obj) then
                local root = obj:FindFirstChild("HumanoidRootPart") 
                          or obj:FindFirstChild("HEAD") 
                          or obj.PrimaryPart
                if root then
                    local dist = (root.Position - minhaPos).Magnitude
                    local vida = getVida(obj)
                    
                    -- ⭐ 1. Dentro do RAIO_ATAQUE
                    if dist <= RAIO_ATAQUE and vida > maiorVidaAtaque then
                        maiorVidaAtaque = vida
                        melhorAtaque = obj
                        distAtaque = dist
                        atributoAtaque = attr
                    end
                    
                    -- ⭐ 2. Dentro do RAIO_BUSCA
                    if dist <= RAIO_BUSCA and vida > maiorVidaBusca then
                        maiorVidaBusca = vida
                        melhorBusca = obj
                        distBusca = dist
                        atributoBusca = attr
                    end
                end
            end
        end
    end
    
    if melhorAtaque then
        return melhorAtaque, atributoAtaque, distAtaque
    end
    return melhorBusca, atributoBusca, distBusca
end

local function tweenarPara(alvo)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not alvo then return end
    local alvoRoot = alvo:FindFirstChild("HumanoidRootPart") 
                  or alvo:FindFirstChild("HEAD") 
                  or alvo.PrimaryPart
    if not alvoRoot then return end
    tweenAtivo = true
    local destino = alvoRoot.CFrame * CFrame.new(0, 0, offsetZ)
    local tween = TweenService:Create(
        hrp, 
        TweenInfo.new(VELOCIDADE_TWEEN, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), 
        { CFrame = destino }
    )
    tween:Play()
    tween.Completed:Connect(function() tweenAtivo = false end)
end

local function enviarRemote(cmd, baton, alvo)
    sendConfirmado = false
    for tentativa = 1, TENTATIVAS do
        pcall(function()
            if cmd == "BatonSwing" then
                NetModule.send("BatonSwing", baton)
            elseif cmd == "BatonHit" then
                NetModule.send("BatonHit", baton, alvo)
            end
        end)
        local inicio = tick()
        while tick() - inicio < 0.05 do
            if sendConfirmado then return true end
            task.wait()
        end
        if not sendConfirmado then
            print("⚠️ Remote", cmd, "falhou. Tentativa", tentativa)
            task.wait(0.05)
        end
    end
    return false
end

local function loopFarm()
    while farmAtivo do
        if tweenAtivo then
            task.wait(LOOP_WAIT)
            continue
        end
        
        local baton = getBaton()
        if not baton then
            task.wait(LOOP_WAIT)
            continue
        end
        
        if not enviouInicial then
            enviouInicial = true
            print("⚡ Envio inicial")
            pcall(function() NetModule.send("BatonSwing", baton) end)
            task.wait(LOOP_WAIT)
            continue
        end
        
        if not alvoVivo(alvoAtual) then
            if alvoAtual then
                local vida = getVida(alvoAtual)
                print("💀 Alvo morreu:", alvoAtual.Name, "| Health:", vida)
            end
            
            local alvo, attr, dist = acharAlvo()
            alvoAtual = alvo
            
            if alvoAtual then
                local vida = getVida(alvoAtual)
                print("🎯 Novo alvo:", alvoAtual.Name, "| Vida:", vida, "| Distância:", math.floor(dist or 0))
                
                pcall(function() NetModule.send("BatonSwing", baton) end)
                
                if (dist or 0) > RAIO_ATAQUE then
                    tweenarPara(alvoAtual)
                end
            else
                print("⏳ Nenhum alvo a", RAIO_BUSCA, "studs. Esperando...")
            end
            task.wait(LOOP_WAIT)
            continue
        end
        
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(LOOP_WAIT) continue end
        
        local alvoRoot = alvoAtual:FindFirstChild("HumanoidRootPart") 
                      or alvoAtual:FindFirstChild("HEAD") 
                      or alvoAtual.PrimaryPart
        if not alvoRoot then task.wait(LOOP_WAIT) continue end
        
        local distancia = (alvoRoot.Position - hrp.Position).Magnitude
        
        -- ⭐ FOLLOW: se afastou mais de 3, tweena
        if distancia > RAIO_FOLLOW then
            tweenarPara(alvoAtual)
            task.wait(VELOCIDADE_TWEEN + 0.05)
            continue
        end
        
        if alvoVivo(alvoAtual) then
            local okSwing = enviarRemote("BatonSwing", baton)
            if okSwing then
                task.wait(0.15)
                if alvoVivo(alvoAtual) then
                    enviarRemote("BatonHit", baton, alvoAtual)
                end
            end
        end
        task.wait(INTERVALO)
    end
end

--// GUI
local gui = Instance.new("ScreenGui")
gui.Name = "BYOLDSCRIPTS"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = guiParent

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 220, 0, 190)
main.Position = UDim2.new(0.5, -110, 0.4, -95)
main.BackgroundColor3 = COR_FUNDO
main.Parent = gui
main.Active = true
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", main)
stroke.Color = COR_BORDA
stroke.Thickness = 2

local title = Instance.new("TextLabel", main)
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Route Zero"
title.TextColor3 = COR_TITULO
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextStrokeTransparency = 0
title.TextStrokeColor3 = Color3.new(0, 0, 0)

local container = Instance.new("Frame", main)
container.Size = UDim2.new(1, -20, 1, -40)
container.Position = UDim2.new(0, 10, 0, 35)
container.BackgroundTransparency = 1
local layout = Instance.new("UIListLayout", container)
layout.Padding = UDim.new(0, 8)

local function createButton(text, cor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.Text = text
    btn.BackgroundColor3 = COR_BG
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = cor
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.TextStrokeTransparency = 0
    btn.TextStrokeColor3 = Color3.new(0, 0, 0)
    btn.Parent = container
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    return btn
end

-- BOTÃO ESP
local btnESP = createButton("👁️ ESP ANOMALY: OFF", COR_ESP)
btnESP.Activated:Connect(function()
    espAtivo = not espAtivo
    if espAtivo then
        btnESP.Text = "👁️ ESP ANOMALY: ON"
        btnESP.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
        print("👁️ ESP ON")
    else
        btnESP.Text = "👁️ ESP ANOMALY: OFF"
        btnESP.BackgroundColor3 = COR_BG
        for model in pairs(highlights) do removerHighlight(model) end
        print("👁️ ESP OFF")
    end
end)

-- BOTÃO AUTO ATTACK
local btnAttack = createButton("⚔️ AUTO ATTACK: OFF", COR_ATTACK)
btnAttack.Activated:Connect(function()
    attackAtivo = not attackAtivo
    if attackAtivo then
        btnAttack.Text = "⚔️ AUTO ATTACK: ON"
        btnAttack.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
        iniciarAttack()
        print("⚔️ Auto-Attack ON")
    else
        btnAttack.Text = "⚔️ AUTO ATTACK: OFF"
        btnAttack.BackgroundColor3 = COR_BG
        pararAttack()
        print("⚔️ Auto-Attack OFF")
    end
end)

-- BOTÃO AUTO-FARM
local btnFarm = createButton("👾 AUTO KILL ANOMALY: OFF", COR_FARM)
btnFarm.Activated:Connect(function()
    farmAtivo = not farmAtivo
    if farmAtivo then
        btnFarm.Text = "👾 AUTO KILL ANOMALY: ON"
        btnFarm.BackgroundColor3 = Color3.fromRGB(50, 25, 55)
        enviouInicial = false
        task.spawn(loopFarm)
        
        task.spawn(function()
            while farmAtivo do
                if offsetZ == -3 then
                    offsetZ = -1
                else
                    offsetZ = -3
                end
                task.wait(0.20)
            end
        end)
        
        print("🤖 Auto-Farm ON (pega o com mais vida + follow 3)")
    else
        btnFarm.Text = "👾 AUTO KILL ANOMALY: OFF"
        btnFarm.BackgroundColor3 = COR_BG
        alvoAtual = nil
        tweenAtivo = false
        enviouInicial = false
        print("🤖 Auto-Farm OFF")
    end
end)

-- DRAG
local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- MONITOR
NetModule.hook("BatonHitFx", function(part, modelo)
    if modelo then
        local vida = getVida(modelo)
        print("💥 HIT:", modelo.Name, "| Health:", vida)
    end
end)

--// NOTIFICAÇÃO FINAL
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Made by Old Scripts";
    Text = "Script loaded";
    Icon = "rbxassetid://15794846967";
    Duration = 6;
    Button1 = "OK";
})

task.spawn(function()
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://3398620867"
    s.Volume = 0.4
    s.Parent = game:GetService("SoundService")
    s:Play()
    task.delay(3, function() s:Destroy() end)
end)

print("[loaded]")
