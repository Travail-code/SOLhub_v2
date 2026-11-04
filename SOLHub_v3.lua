--[[
    SOL Hub v3.0
    Key system - loader - main hub (Home / Games / Settings) - themes - notifications
    Built to run on a wide range of executors (Xeno, Delta, Solara, Wave, Synapse-like...)
]]

local Config = {
    HubName      = "SOL Hub",
    Version      = "v3.0",
    SiteURL      = "https://TON-SITE.com",
    KeyCheckURL  = nil,
    KeyFile      = "SOLHub_Key.txt",
    SettingsFile = "SOLHub_Settings.json",
    MaxAttempts  = 5,
    LockSeconds  = 15,
}

local ValidKeys = {
    "SOL-KEY-1A9X",
    "SOL-KEY-2B7K",
    "SOL-KEY-3C4M",
    "SOL-KEY-4D8P",
    "SOL-KEY-5E2Q",
}

local Games = {
    { Name = "Blox Fruits",      Url = "https://raw.githubusercontent.com/tonlien/bloxfruits.lua" },
    { Name = "Pet Simulator 99", Url = "https://raw.githubusercontent.com/tonlien/ps99.lua" },
    { Name = "Adopt Me",         Url = "https://raw.githubusercontent.com/tonlien/adoptme.lua" },
    { Name = "Brookhaven",       Url = "https://raw.githubusercontent.com/tonlien/brookhaven.lua" },
    { Name = "Arsenal",          Url = "https://raw.githubusercontent.com/tonlien/arsenal.lua" },
}

----------------------------------------------------------------------------------------------------
-- Compatibility layer
----------------------------------------------------------------------------------------------------

-- task library fallback (very old / stripped environments)
local task = task
if type(task) ~= "table" or type(task.spawn) ~= "function" then
    local unpackFn = (table and table.unpack) or unpack
    task = {}
    task.spawn = function(f, ...)
        local co = coroutine.create(f)
        local ok, err = coroutine.resume(co, ...)
        if not ok then warn("[SOL Hub] " .. tostring(err)) end
        return co
    end
    task.defer = task.spawn
    task.wait = function(t) return wait(t) end
    task.delay = function(t, f, ...)
        local args = { n = select("#", ...), ... }
        return task.spawn(function()
            wait(t)
            f(unpackFn(args, 1, args.n))
        end)
    end
end

local Clock = (os and os.clock) or tick or function() return 0 end

local function ClearTable(t)
    if table.clear then
        table.clear(t)
    else
        for k in pairs(t) do t[k] = nil end
    end
end

-- first argument that is a function (safe with nils in between)
local function FirstFn(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
    return nil
end

local function SafeIndex(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local ok, v = pcall(function() return tbl[key] end)
    if ok then return v end
    return nil
end

local env
if type(getgenv) == "function" then
    local ok, e = pcall(getgenv)
    if ok and type(e) == "table" then env = e end
end
if not env and type(_G) == "table" then env = _G end
-- make sure we can actually write to it (some sandboxes freeze _G)
if not env or not pcall(function() env.__SOLHub_probe = true; env.__SOLHub_probe = nil end) then
    env = {}
end

local function Service(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if not ok or not s then return nil end
    local clone = FirstFn(cloneref, SafeIndex(env, "cloneref"))
    if clone then
        local ok2, c = pcall(clone, s)
        if ok2 and typeof(c) == "Instance" then return c end
    end
    return s
end

pcall(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
end)

local Players          = Service("Players")
local TweenService     = Service("TweenService")
local UserInputService = Service("UserInputService")
local RunService       = Service("RunService")
local HttpService      = Service("HttpService")
local Workspace        = Service("Workspace") or workspace

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    pcall(function() Players:GetPropertyChangedSignal("LocalPlayer"):Wait() end)
    LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then task.wait(0.1) end
end

-- executor functions (resolved once, every call is pcall-wrapped)
local LoadStringFn = FirstFn(loadstring, SafeIndex(env, "loadstring"))
local WriteFileFn  = FirstFn(writefile, SafeIndex(env, "writefile"))
local ReadFileFn   = FirstFn(readfile, SafeIndex(env, "readfile"))
local IsFileFn     = FirstFn(isfile, SafeIndex(env, "isfile"))
local DelFileFn    = FirstFn(delfile, SafeIndex(env, "delfile"))
local GetHuiFn     = FirstFn(gethui, get_hidden_gui, SafeIndex(env, "gethui"))
local ProtectGuiFn = FirstFn(SafeIndex(syn, "protect_gui"), protectgui, protect_gui, SafeIndex(env, "protect_gui"))
local RequestFn    = FirstFn(
    request, http_request, SafeIndex(syn, "request"), SafeIndex(http, "request"),
    SafeIndex(fluxus, "request"), SafeIndex(env, "request")
)
local ClipboardFn  = FirstFn(
    setclipboard, toclipboard, set_clipboard, setrbxclipboard,
    SafeIndex(Clipboard, "set"), SafeIndex(syn, "write_clipboard"), SafeIndex(env, "setclipboard")
)
local ExecNameFn   = FirstFn(identifyexecutor, getexecutorname, whatexecutor, SafeIndex(env, "identifyexecutor"))

local FS = {}
function FS.Write(path, content)
    if not WriteFileFn then return false end
    return (pcall(WriteFileFn, path, content))
end
function FS.Read(path)
    if not ReadFileFn then return nil end
    if IsFileFn then
        local ok, exists = pcall(IsFileFn, path)
        if ok and exists == false then return nil end
    end
    local ok, res = pcall(ReadFileFn, path)
    if ok and type(res) == "string" then return res end
    return nil
end
function FS.Delete(path)
    if DelFileFn and FS.Read(path) ~= nil then
        if pcall(DelFileFn, path) then return true end
    end
    -- no delfile: blank the file instead (an empty key is treated as "no key")
    return FS.Write(path, "")
end

local function HttpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(res) == "string" then return res end
    ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" then return res end
    ok, res = pcall(function() return game:HttpGetAsync(url) end)
    if ok and type(res) == "string" then return res end
    if RequestFn then
        local ok2, r = pcall(RequestFn, { Url = url, Method = "GET" })
        if ok2 and type(r) == "table" then
            local code = tonumber(r.StatusCode) or 200
            if type(r.Body) == "string" and r.Success ~= false and code >= 200 and code < 300 then
                return r.Body
            end
            error("HTTP " .. tostring(r.StatusCode or "error"), 0)
        end
    end
    error("HttpGet is not supported on this executor", 0)
end

local function SetClipboard(text)
    if not ClipboardFn then return false end
    return (pcall(ClipboardFn, text))
end

local function ExecutorName()
    if not ExecNameFn then return "Unknown" end
    local ok, name, ver = pcall(ExecNameFn)
    if not ok or name == nil then return "Unknown" end
    name = tostring(name)
    if ver ~= nil and tostring(ver) ~= "" and not string.find(name, tostring(ver), 1, true) then
        name = name .. " " .. tostring(ver)
    end
    return name
end

local function KeyCodeFrom(name)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    if ok and typeof(kc) == "EnumItem" then return kc end
    return nil
end

local function IsTouchOnly()
    local ok, res = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end)
    return ok and res == true
end

local function JSONEncode(t)
    local ok, s = pcall(function() return HttpService:JSONEncode(t) end)
    return ok and s or nil
end

local function JSONDecode(s)
    local ok, t = pcall(function() return HttpService:JSONDecode(s) end)
    return (ok and type(t) == "table") and t or nil
end

local function UrlEncode(s)
    local ok, r = pcall(function() return HttpService:UrlEncode(s) end)
    if ok and type(r) == "string" then return r end
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

if type(env.SOLHub_Unload) == "function" then pcall(env.SOLHub_Unload) end

local Alive = true
local Trash = {}
local GlowLayers = {} -- holder -> { layers = {Frame...}, key = themeKey|nil }, strong keys, cleaned on Destroying / unload
local Registry = {} -- strong table: obj -> { prop = themeKey }, cleaned on Destroying / unload

local function Track(x)
    Trash[#Trash + 1] = x
    return x
end

env.SOLHub_Unload = function()
    Alive = false
    for i = #Trash, 1, -1 do
        local x = Trash[i]
        pcall(function()
            if typeof(x) == "RBXScriptConnection" then x:Disconnect() else x:Destroy() end
        end)
    end
    ClearTable(Trash)
    ClearTable(Registry)
    ClearTable(GlowLayers)
end

----------------------------------------------------------------------------------------------------
-- Assets / themes
----------------------------------------------------------------------------------------------------

local Icons = {
    ["gamepad-2"]    = "rbxassetid://92483947987410",
    ["settings"]     = "rbxassetid://80758916183665",
    ["search"]       = "rbxassetid://121018724060431",
    ["x"]            = "rbxassetid://110786993356448",
    ["minus"]        = "rbxassetid://118026365011536",
    ["key"]          = "rbxassetid://96510194465420",
    ["power"]        = "rbxassetid://96479131758775",
    ["palette"]      = "rbxassetid://86350350950064",
    ["monitor"]      = "rbxassetid://72664649203050",
    ["chevron-down"] = "rbxassetid://134243273101015",
    ["user"]         = "rbxassetid://81589895647169",
    ["check"]        = "rbxassetid://93898873302694",
    ["copy"]         = "rbxassetid://78979572434545",
    ["trash-2"]      = "rbxassetid://109843431391323",
    ["play"]         = "rbxassetid://135609604299893",
    ["shield-check"] = "rbxassetid://87354736164608",
    ["external-link"]= "rbxassetid://129331830773832",
    ["info"]         = "rbxassetid://124560466474914",
    ["layout-grid"]  = "rbxassetid://81344910161871",
}
local SHADOW = "rbxassetid://6014261993"

local function P(bg, s, s2, s3, st, sth, ac, acd, tx, mu)
    local function c(t) return Color3.fromRGB(t[1], t[2], t[3]) end
    return {
        Background = c(bg), Surface = c(s), Surface2 = c(s2), Surface3 = c(s3),
        Stroke = c(st), StrokeHover = c(sth), Accent = c(ac), AccentDark = c(acd),
        Text = c(tx), Muted = c(mu),
    }
end

local Presets = {
    Mono     = P({16,16,17},{20,20,21},{25,25,26},{40,40,42},{38,38,40},{84,84,88},{236,236,240},{20,20,22},{234,234,236},{128,128,134}),
    Midnight = P({15,18,26},{18,22,31},{22,26,37},{37,44,60},{34,40,55},{70,84,112},{128,160,246},{14,18,30},{228,232,242},{124,134,156}),
    Ocean    = P({12,20,24},{15,24,29},{18,29,35},{31,48,56},{29,44,52},{58,92,104},{110,214,222},{10,24,28},{226,238,240},{116,142,148}),
    Emerald  = P({13,20,17},{16,24,20},{20,29,24},{33,47,40},{30,44,37},{62,96,78},{132,226,170},{12,26,18},{228,240,233},{118,144,130}),
    Amber    = P({22,18,13},{27,22,16},{32,26,19},{49,41,31},{46,38,28},{100,82,58},{246,196,120},{30,22,10},{242,236,226},{148,134,114}),
    Nebula   = P({14,12,28},{18,15,35},{23,19,43},{39,32,68},{35,29,62},{84,68,140},{199,125,255},{22,10,40},{236,230,252},{132,122,168}),
    Crimson  = P({18,10,12},{23,12,15},{28,14,18},{46,24,29},{42,22,27},{104,46,56},{244,74,94},{32,8,12},{244,230,232},{150,114,120}),
}
local PresetOrder = { "Mono", "Midnight", "Ocean", "Emerald", "Amber", "Nebula", "Crimson" }

-- per-game accent tints for banners / monograms (picked by position, the Games table stays untouched)
local GameTints = {
    Color3.fromRGB(92, 160, 255),
    Color3.fromRGB(255, 190, 92),
    Color3.fromRGB(255, 124, 182),
    Color3.fromRGB(96, 214, 156),
    Color3.fromRGB(255, 118, 96),
    Color3.fromRGB(168, 132, 255),
    Color3.fromRGB(84, 214, 230),
}
local function TintFor(i)
    return GameTints[((i - 1) % #GameTints) + 1]
end

local State = {
    Theme = "Mono",
    Notifs = true,
    RememberKey = true,
    ToggleKey = "RightShift",
}
local Theme = {}

local function BuildTheme()
    ClearTable(Theme)
    for k, v in pairs(Presets[State.Theme] or Presets.Mono) do Theme[k] = v end
    Theme.Success = Color3.fromRGB(110, 220, 150)
    Theme.Warning = Color3.fromRGB(240, 176, 108)
    Theme.Error   = Color3.fromRGB(240, 110, 110)
end

local function SaveSettings()
    local data = JSONEncode({
        theme = State.Theme,
        notifs = State.Notifs,
        rememberKey = State.RememberKey,
        toggleKey = State.ToggleKey,
    })
    if data then FS.Write(Config.SettingsFile, data) end
end

local function LoadSettings()
    local raw = FS.Read(Config.SettingsFile)
    if not raw or raw == "" then return end
    local d = JSONDecode(raw)
    if not d then return end
    if type(d.theme) == "string" and Presets[d.theme] then State.Theme = d.theme end
    if type(d.notifs) == "boolean" then State.Notifs = d.notifs end
    if type(d.rememberKey) == "boolean" then State.RememberKey = d.rememberKey end
    if KeyCodeFrom(d.toggleKey) then State.ToggleKey = d.toggleKey end
end

----------------------------------------------------------------------------------------------------
-- UI primitives
----------------------------------------------------------------------------------------------------

local function Tween(obj, props, time, style, dir)
    local ok, t = pcall(function()
        return TweenService:Create(
            obj,
            TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
            props
        )
    end)
    if ok and t then
        t:Play()
        return t
    end
    -- tween failed: apply instantly
    pcall(function() for k, v in pairs(props) do obj[k] = v end end)
    return nil
end

local function Bind(obj, prop, key, t)
    local entry = Registry[obj]
    if not entry then
        entry = {}
        Registry[obj] = entry
        pcall(function()
            obj.Destroying:Connect(function() Registry[obj] = nil end)
        end)
    end
    entry[prop] = key
    if t == false then return end
    if t then
        Tween(obj, { [prop] = Theme[key] }, t)
    else
        pcall(function() obj[prop] = Theme[key] end)
    end
end

local function ApplyTheme()
    BuildTheme()
    for obj, props in pairs(Registry) do
        local okParent, parent = pcall(function() return obj.Parent end)
        if not okParent then
            Registry[obj] = nil
        elseif parent then
            for prop, key in pairs(props) do
                Tween(obj, { [prop] = Theme[key] }, 0.3)
            end
        end
    end
    -- themed glows: one plain loop per glow (no Registry entries, no tweens)
    for holder, info in pairs(GlowLayers) do
        if info.key then
            local c = Theme[info.key]
            for _, f in ipairs(info.layers) do
                pcall(function() f.BackgroundColor3 = c end)
            end
        end
    end
end

local function New(class, props, themed)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then
        o.BorderSizePixel = 0
        pcall(function() o.AutoLocalize = false end)
    end
    if o:IsA("TextLabel") then
        o.BackgroundTransparency = 1
        o.Font = Enum.Font.Gotham
    end
    if o:IsA("TextButton") then
        o.AutoButtonColor = false
        o.Font = Enum.Font.Gotham
    end
    if o:IsA("TextBox") then o.Font = Enum.Font.Gotham end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then o.BackgroundTransparency = 1 end

    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            local ok, err = pcall(function() o[k] = v end)
            if not ok then
                warn("[SOL Hub] invalid property " .. class .. "." .. tostring(k) .. " : " .. tostring(err))
            end
        end
    end
    for prop, key in pairs(themed or {}) do Bind(o, prop, key) end
    if parent then o.Parent = parent end
    return o
end

local function Round(obj, r)
    return New("UICorner", {
        CornerRadius = (r == "full") and UDim.new(1, 0) or UDim.new(0, r),
        Parent = obj,
    })
end

local function Outline(obj, key, thickness, transparency)
    return New("UIStroke", {
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = obj,
    }, { Color = key or "Stroke" })
end

-- transparency gradient (works with themed colours because it only fades)
local function Fade(obj, from, to, rotation)
    return New("UIGradient", {
        Parent = obj,
        Rotation = rotation or 0,
        Transparency = NumberSequence.new(from, to),
    })
end

-- colour gradient multiplier (white -> grey = accent -> darker accent)
local function Shade(obj, dark, rotation)
    return New("UIGradient", {
        Parent = obj,
        Rotation = rotation or 45,
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(dark, dark, dark)),
    })
end

-- lit rim: one stroke that is bright on the top edge and fades out toward the bottom
-- (fake inner highlight, gives surfaces a glassy layered look)
local function Rim(obj, key, top, bottom, thickness)
    local s = Outline(obj, key or "StrokeHover", thickness or 1, 0)
    New("UIGradient", {
        Parent = s,
        Rotation = 90,
        Transparency = NumberSequence.new(top or 0.25, bottom or 0.8),
    })
    return s
end

-- multi-stop transparency gradient helper: Stops({ {0, 1}, {0.5, 0.8}, {1, 1} })
local function Stops(list)
    local kps = {}
    for i, v in ipairs(list) do kps[i] = NumberSequenceKeypoint.new(v[1], v[2]) end
    return NumberSequence.new(kps)
end

local function Label(parent, text, size, colorKey, font, props)
    local p = {
        Parent = parent,
        Text = text,
        TextSize = size,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("TextLabel", p, { TextColor3 = colorKey or "Text" })
end

local function Icon(parent, name, size, colorKey, props)
    local p = {
        Parent = parent,
        Size = UDim2.fromOffset(size, size),
        Image = Icons[name] or "",
        ScaleType = Enum.ScaleType.Fit,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("ImageLabel", p, { ImageColor3 = colorKey or "Muted" })
end

local function Shadow(parent, transparency)
    return New("ImageLabel", {
        Parent = parent,
        Position = UDim2.fromOffset(-28, -28),
        Size = UDim2.new(1, 56, 1, 56),
        Image = SHADOW,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = transparency or 0.5,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
    })
end

-- soft coloured glow, built only from rounded Frames (no image asset).
-- The old version tinted a black shadow image, and since ImageColor3 multiplies,
-- black x accent stayed black: in game the halos showed up as dark smudges.
-- Here concentric pills are stacked; their alphas add up toward the centre,
-- which gives a soft radial light that renders the same on every executor.
-- Valid transparency range: 0.4 .. 1 (1 = invisible).
local function glowLayerT(transparency, n)
    local T = math.clamp(transparency or 0.6, 0, 1)
    if T >= 1 then return 1 end
    -- softened x0.8 so the glow stays discreet,
    -- floored at 0.05 so the centre never becomes a solid disc
    T = math.max(0.05, 1 - (1 - T) * 0.8)
    -- each layer's transparency t such that the centre (all n stacked) has t^n = boosted T
    return T ^ (1 / n)
end

local function SoftGlow(parent, color, pos, size, transparency, z, anchor)
    local themed = type(color) == "string"
    local function side(d) return d.Scale > 0 and 200 or d.Offset end
    local maxSide = math.max(side(size.X), side(size.Y))
    local n = math.clamp(math.floor(maxSide / 10), 8, 20)
    local holder = New("Frame", {
        Parent = parent,
        Name = "Glow",
        AnchorPoint = anchor or Vector2.new(0.5, 0.5),
        Position = pos,
        Size = size,
        BackgroundTransparency = 1,
        Visible = (transparency or 0.6) < 1,
        ZIndex = z or 1,
    })
    local layerT = glowLayerT(transparency, n)
    local c = themed and Theme[color] or color
    local layers = {}
    for i = 1, n do
        local k = 0.62 - (i - 1) * (0.5 / math.max(n - 1, 1)) -- 0.62 -> 0.12 (tight around the icon)
        local f = New("Frame", {
            Parent = holder,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(k, k),
            BackgroundColor3 = c,
            BackgroundTransparency = layerT,
            ZIndex = z or 1,
        })
        Round(f, "full")
        layers[i] = f
    end
    GlowLayers[holder] = { layers = layers, key = themed and color or nil }
    pcall(function() holder:SetAttribute("GlowT", transparency or 0.6) end)
    pcall(function()
        holder.Destroying:Connect(function() GlowLayers[holder] = nil end)
    end)
    return holder
end

-- fade a glow made by SoftGlow to a new overall transparency
local function GlowFade(holder, transparency, duration)
    local info = GlowLayers[holder]
    if not info then return end
    pcall(function() holder:SetAttribute("GlowT", transparency) end)
    local t = glowLayerT(transparency, #info.layers)
    if transparency < 1 then holder.Visible = true end
    local last
    for _, f in ipairs(info.layers) do
        last = Tween(f, { BackgroundTransparency = t }, duration or 0.2) or last
    end
    if transparency >= 1 then
        local function hide()
            local okA, cur = pcall(function() return holder:GetAttribute("GlowT") end)
            if not okA or cur == nil or cur >= 1 then holder.Visible = false end
        end
        if last then
            pcall(function() last.Completed:Connect(hide) end)
        else
            hide()
        end
    end
end

-- brand mark: soft accent glow + shaded accent tile with a lit rim and the "S"
local function Logo(parent, pos, size, radius, textSize, z, glowScale)
    z = z or 1
    local g = glowScale or 2.3
    local cx, cy = pos.X.Offset + size / 2, pos.Y.Offset + size / 2
    local halo = SoftGlow(parent, "Accent",
        UDim2.new(pos.X.Scale, cx, pos.Y.Scale, cy),
        UDim2.fromOffset(size * g, size * g), 0.72, z)
    local tile = New("Frame", {
        Parent = parent,
        Position = pos,
        Size = UDim2.fromOffset(size, size),
        ZIndex = z + 1,
    }, { BackgroundColor3 = "Accent" })
    Round(tile, radius)
    Shade(tile, 0.68, 60)
    Rim(tile, "Text", 0.35, 1)
    -- glossy top half
    local gloss = New("Frame", {
        Parent = tile,
        Size = UDim2.fromScale(1, 0.55),
        BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = z + 1,
    })
    Round(gloss, radius)
    Fade(gloss, 0.78, 1, 90)
    Label(tile, "S", textSize, "AccentDark", Enum.Font.GothamBlack, {
        Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = z + 2,
    })
    return tile, halo
end

local function SafeParent(gui, parent)
    if not parent then return false end
    pcall(function()
        local old = parent:FindFirstChild(gui.Name)
        if old and old ~= gui then old:Destroy() end
    end)
    local ok = pcall(function() gui.Parent = parent end)
    return ok and gui.Parent == parent
end

local function MountGui(name, order)
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = order or 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() gui.AutoLocalize = false end)
    pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)

    if ProtectGuiFn then pcall(ProtectGuiFn, gui) end

    -- 1) hidden UI container (most executors)
    if GetHuiFn then
        local ok, hui = pcall(GetHuiFn)
        if ok and typeof(hui) == "Instance" and SafeParent(gui, hui) then return gui end
    end
    -- 2) CoreGui (needs elevated identity, fails silently on some executors)
    local core = Service("CoreGui")
    if core and SafeParent(gui, core) then return gui end
    -- 3) PlayerGui (always works)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then
        local ok, res = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 10) end)
        if ok then pg = res end
    end
    if not SafeParent(gui, pg) then warn("[SOL Hub] could not mount " .. name) end
    return gui
end

local function Viewport()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize
    if not vp or vp.X < 2 or vp.Y < 2 then vp = Vector2.new(1280, 720) end
    return vp
end

local function FitScale(w, h)
    local vp = Viewport()
    local margin = (vp.X < 900) and 16 or 32
    return math.clamp(math.min((vp.X - margin) / w, (vp.Y - margin) / h), 0.4, 1)
end

-- fires callback whenever the screen size changes (rotation on phones, window resize on PC)
local function OnViewportChanged(callback)
    local camConn
    local function hook()
        if camConn then camConn:Disconnect() end
        local cam = Workspace.CurrentCamera
        if cam then
            camConn = Track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(callback))
        end
    end
    hook()
    Track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        hook()
        callback()
    end))
end

local function PopIn(root, w, h)
    local target = FitScale(w, h)
    local s = New("UIScale", { Scale = target * 0.9, Parent = root })
    Tween(s, { Scale = target }, 0.45, Enum.EasingStyle.Back)
    return s, target
end

-- mouse + touch dragging. returns a function telling if the last press was a drag
local function MakeDraggable(frame, handle)
    local MB1, Touch = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
    local dragging, dragInput, dragStart, startPos, moved = false, nil, nil, nil, false

    Track(handle.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then
            dragging = true
            moved = false
            dragInput = input
            dragStart = input.Position
            startPos = frame.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if c then c:Disconnect() end
                end
            end)
        end
    end))

    Track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local t = input.UserInputType
        local isTouchDrag = t == Touch and dragInput and dragInput.UserInputType == Touch
        if t == Enum.UserInputType.MouseMovement or isTouchDrag then
            local d = input.Position - dragStart
            if math.abs(d.X) + math.abs(d.Y) > 6 then moved = true end
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end))

    Track(UserInputService.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then dragging = false end
    end))

    return function() return moved end
end

-- press feedback (UIScale squeeze) for any button
local function Pressable(btn, amount)
    local s = New("UIScale", { Parent = btn, Scale = 1 })
    btn.MouseButton1Down:Connect(function() Tween(s, { Scale = amount or 0.96 }, 0.1) end)
    btn.MouseButton1Up:Connect(function() Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back) end)
    btn.MouseLeave:Connect(function() Tween(s, { Scale = 1 }, 0.2) end)
    return s
end

local function Ripple(host)
    local size = math.max(host.AbsoluteSize.X, host.AbsoluteSize.Y) * 2.2
    local r = New("Frame", {
        Parent = host,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.85,
        ZIndex = host.ZIndex + 1,
    })
    Round(r, "full")
    Tween(r, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, 0.5)
    task.delay(0.55, function() pcall(function() r:Destroy() end) end)
end

local function Chip(props)
    local style = props.Style or "default"
    local primary = style == "primary"
    local danger = style == "danger"
    local baseT = primary and 0 or 0.35

    local btn = New("TextButton", {
        Parent = props.Parent,
        Size = props.Size,
        Position = props.Position,
        AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
        LayoutOrder = props.LayoutOrder or 0,
        Text = "",
        ClipsDescendants = true,
        BackgroundTransparency = baseT,
        ZIndex = props.ZIndex or 1,
    }, { BackgroundColor3 = primary and "Accent" or "Surface3" })
    Round(btn, props.Radius or 8)
    local stroke
    if primary then
        Shade(btn, 0.78, 90)
        stroke = Rim(btn, "Text", 0.45, 1)
        local gloss = New("Frame", {
            Parent = btn,
            Size = UDim2.fromScale(1, 0.5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            ZIndex = btn.ZIndex,
        })
        Round(gloss, props.Radius or 8)
        Fade(gloss, 0.84, 1, 90)
    else
        stroke = Rim(btn, "StrokeHover", 0.35, 0.85)
    end
    Pressable(btn)

    local content = New("Frame", {
        Parent = btn,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = btn.ZIndex + 1,
    })
    New("UIListLayout", {
        Parent = content,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    })

    local textKey = primary and "AccentDark" or (danger and "Error" or "Text")
    local iconKey = primary and "AccentDark" or (danger and "Error" or "Accent")
    if props.Icon then
        Icon(content, props.Icon, props.IconSize or 14, iconKey, { LayoutOrder = 1, ZIndex = btn.ZIndex + 1 })
    end
    local label = Label(content, props.Text or "", props.TextSize or 13, textKey,
        primary and Enum.Font.GothamBold or Enum.Font.GothamMedium, {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        ZIndex = btn.ZIndex + 1,
    })

    btn.MouseEnter:Connect(function()
        if primary then
            Tween(btn, { BackgroundTransparency = 0.12 }, 0.12)
        else
            Tween(btn, { BackgroundTransparency = 0 }, 0.12)
            Bind(stroke, "Color", danger and "Error" or "Accent", 0.12)
        end
    end)
    btn.MouseLeave:Connect(function()
        Tween(btn, { BackgroundTransparency = baseT }, 0.25)
        if not primary then
            Bind(stroke, "Color", "StrokeHover", 0.25)
        end
    end)
    btn.MouseButton1Click:Connect(function()
        Ripple(btn)
        if props.Callback then task.spawn(props.Callback) end
    end)

    return btn, label
end

local function IconButton(parent, iconName, position, callback, hoverKey)
    local b = New("TextButton", {
        Parent = parent,
        AnchorPoint = Vector2.new(1, 0),
        Position = position,
        Size = UDim2.fromOffset(32, 32),
        Text = "",
        BackgroundTransparency = 0.3,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(b, 9)
    local stroke = Rim(b, "StrokeHover", 0.3, 0.85)
    Pressable(b, 0.9)
    local ic = Icon(b, iconName, 16, "Muted", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        ZIndex = 4,
    })
    b.MouseEnter:Connect(function()
        Tween(b, { BackgroundTransparency = 0 }, 0.12)
        Bind(ic, "ImageColor3", hoverKey or "Text", 0.12)
        Bind(stroke, "Color", hoverKey or "StrokeHover", 0.12)
    end)
    b.MouseLeave:Connect(function()
        Tween(b, { BackgroundTransparency = 0.3 }, 0.2)
        Bind(ic, "ImageColor3", "Muted", 0.2)
        Bind(stroke, "Color", "StrokeHover", 0.2)
    end)
    b.MouseButton1Click:Connect(function()
        if callback then task.spawn(callback) end
    end)
    return b
end

----------------------------------------------------------------------------------------------------
-- Key logic
----------------------------------------------------------------------------------------------------

local function Normalize(s)
    return (tostring(s or ""):gsub("%s+", "")):upper()
end

local function SaveKey(key)
    FS.Write(Config.KeyFile, key)
end

local function LoadKey()
    local raw = FS.Read(Config.KeyFile)
    if not raw then return nil end
    local k = Normalize(raw)
    if k == "" then return nil end
    return k
end

local function ForgetKey()
    FS.Delete(Config.KeyFile)
end

local function CheckKey(input)
    local key = Normalize(input)
    if key == "" then return false end

    if Config.KeyCheckURL then
        local ok, res = pcall(HttpGet, Config.KeyCheckURL .. UrlEncode(key))
        return ok and (tostring(res):gsub("%s+", ""):lower() == "true")
    end

    for _, k in ipairs(ValidKeys) do
        if key == k:upper() then return true end
    end
    return false
end

local function RunGame(g)
    return pcall(function()
        if not LoadStringFn then error("loadstring is not available on this executor", 0) end
        local src = g.Script
        if not src then src = HttpGet(g.Url) end
        if type(src) ~= "string" or src == "" then error("Empty script response", 0) end
        local fn, err = LoadStringFn(src)
        if not fn then error(tostring(err), 0) end
        fn()
    end)
end

----------------------------------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------------------------------

local NotifGui, NotifHolder

local function EnsureNotifs()
    if NotifGui and NotifGui.Parent and NotifHolder and NotifHolder.Parent then return end
    NotifGui = Track(MountGui("SOLHub_Notifs", 1000))
    NotifHolder = New("Frame", {
        Parent = NotifGui,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.new(0, 300, 1, -36),
        BackgroundTransparency = 1,
    })
    New("UIListLayout", {
        Parent = NotifHolder,
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    })
    local vp = Viewport()
    if vp.X < 700 then
        New("UIScale", { Parent = NotifHolder, Scale = math.max(vp.X / 700, 0.7) })
    end
end

local NotifOrder = 0
local function Notify(title, text, kind, duration)
    if not Alive then return end
    if not State.Notifs and kind ~= "error" then return end
    EnsureNotifs()
    duration = duration or 3.5
    NotifOrder = NotifOrder + 1

    local color = (kind == "success" and Theme.Success) or (kind == "error" and Theme.Error) or Theme.Accent
    local iconName = (kind == "success" and "check") or (kind == "error" and "x") or "info"

    local wrap = New("Frame", {
        Parent = NotifHolder,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 64),
        ClipsDescendants = true,
        LayoutOrder = NotifOrder,
    })
    local card = New("TextButton", {
        Parent = wrap,
        Text = "",
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.new(1, 24, 0, 0),
        BackgroundColor3 = Theme.Surface2,
    })
    Round(card, 12)
    local cs = New("UIStroke", { Parent = card, Color = Theme.StrokeHover, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    New("UIGradient", { Parent = cs, Rotation = 90, Transparency = NumberSequence.new(0.2, 0.8) })

    local glow = New("Frame", {
        Parent = card,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = color,
        BackgroundTransparency = 0,
    })
    Round(glow, 12)
    Fade(glow, 0.84, 1, 0)

    -- accent strip on the left edge
    local strip = New("Frame", {
        Parent = card,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 28),
        BackgroundColor3 = color,
        ZIndex = 2,
    })
    Round(strip, "full")

    SoftGlow(card, color, UDim2.fromOffset(31, 32), UDim2.fromOffset(78, 78), 0.8, 1)

    local tile = New("Frame", {
        Parent = card,
        Size = UDim2.fromOffset(34, 34),
        Position = UDim2.fromOffset(14, 15),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.82,
        ZIndex = 2,
    })
    Round(tile, 10)
    New("UIStroke", { Parent = tile, Color = color, Transparency = 0.6, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    New("ImageLabel", {
        Parent = tile,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        Image = Icons[iconName],
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 3,
    })

    New("TextLabel", {
        Parent = card,
        Text = tostring(title),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(60, 14),
        Size = UDim2.new(1, -74, 0, 16),
        ZIndex = 2,
    })
    New("TextLabel", {
        Parent = card,
        Text = tostring(text),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(60, 33),
        Size = UDim2.new(1, -74, 0, 16),
        ZIndex = 2,
    })

    local bar = New("Frame", {
        Parent = card,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 14, 1, -1),
        Size = UDim2.new(1, -28, 0, 2),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.15,
        ZIndex = 2,
    })
    Round(bar, "full")
    Fade(bar, 0.6, 0, 0)

    local closed = false
    local function close()
        if closed then return end
        closed = true
        if card.Parent then
            Tween(card, { Position = UDim2.new(1, 24, 0, 0) }, 0.28)
            task.wait(0.3)
            Tween(wrap, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
            task.wait(0.21)
        end
        pcall(function() wrap:Destroy() end)
    end

    card.MouseButton1Click:Connect(function() task.spawn(close) end)
    Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.4, Enum.EasingStyle.Back)
    Tween(bar, { Size = UDim2.new(0, 0, 0, 2) }, duration, Enum.EasingStyle.Linear)
    task.delay(duration, close)
end

----------------------------------------------------------------------------------------------------
-- Loader
----------------------------------------------------------------------------------------------------

local function ShowLoader(onDone)
    local gui = Track(MountGui("SOLHub_Loader", 950))
    local steps = { "Verifying key", "Loading interface", "Almost ready" }
    local W = 360
    local rowsTop = 92
    local H = rowsTop + #steps * 30 + 44

    local root = New("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = 1,
    })
    Shadow(root, 0.45)
    local card = New("Frame", {
        Parent = root,
        Size = UDim2.fromScale(1, 1),
        ClipsDescendants = true,
        ZIndex = 2,
    }, { BackgroundColor3 = "Background" })
    Round(card, 16)
    Rim(card, "StrokeHover", 0.1, 0.75)
    local glow = New("Frame", {
        Parent = card, Size = UDim2.new(1, 0, 0, 110), ZIndex = 2,
    }, { BackgroundColor3 = "Accent" })
    Round(glow, 16)
    Fade(glow, 0.86, 1, 90)
    local scale, target = PopIn(root, W, H)

    Logo(card, UDim2.fromOffset(24, 24), 40, 12, 21, 3)
    Label(card, Config.HubName, 16, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(78, 26), Size = UDim2.fromOffset(170, 18), ZIndex = 4,
    })
    Label(card, "Preparing your session", 12, "Muted", nil, {
        Position = UDim2.fromOffset(78, 46), Size = UDim2.fromOffset(170, 14), ZIndex = 4,
    })
    local pct = Label(card, "0%", 22, "Text", Enum.Font.GothamBlack, {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 29),
        Size = UDim2.fromOffset(70, 26), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4,
    })
    local sep = New("Frame", {
        Parent = card, Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 1), ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = sep, Transparency = Stops({ { 0, 1 }, { 0.2, 0 }, { 0.8, 0 }, { 1, 1 } }) })

    local rows = {}
    for i, text in ipairs(steps) do
        local row = New("Frame", {
            Parent = card, BackgroundTransparency = 1, ZIndex = 3,
            Position = UDim2.fromOffset(24, rowsTop + (i - 1) * 30),
            Size = UDim2.new(1, -48, 0, 30),
        })
        local dot = New("Frame", {
            Parent = row, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(7, 7), ZIndex = 3,
        }, { BackgroundColor3 = "Surface3" })
        Round(dot, "full")
        local check = Icon(row, "check", 14, "Accent", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
            ImageTransparency = 1, ZIndex = 3,
        })
        local lbl = Label(row, text, 13, "Muted", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), ZIndex = 3,
        })
        rows[i] = { dot = dot, check = check, lbl = lbl }
    end

    local track = New("Frame", {
        Parent = card, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24),
        Size = UDim2.new(1, -48, 0, 6), ZIndex = 3,
    }, { BackgroundColor3 = "Surface3" })
    Round(track, "full")
    local fill = New("Frame", {
        Parent = track, Size = UDim2.fromScale(0, 1), ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(fill, "full")
    Fade(fill, 0.55, 0, 0)
    -- bright head on the progress bar
    local head = New("Frame", {
        Parent = fill, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(6, 6), ZIndex = 5,
    }, { BackgroundColor3 = "Text" })
    Round(head, "full")
    local headGlow = SoftGlow(card, "Accent", UDim2.new(0, 24, 1, -27), UDim2.fromOffset(54, 54), 0.8, 2)

    local function setStep(i, s)
        local r = rows[i]
        if not r then return end
        if s == "active" then
            Bind(r.lbl, "TextColor3", "Text", 0.2)
            Bind(r.dot, "BackgroundColor3", "Accent", 0.2)
        elseif s == "done" then
            r.dot.Visible = false
            Tween(r.check, { ImageTransparency = 0 }, 0.2)
            Bind(r.lbl, "TextColor3", "Muted", 0.2)
        end
    end

    local D = 1.5
    Tween(fill, { Size = UDim2.fromScale(1, 1) }, D, Enum.EasingStyle.Quart)

    local conn = Track(RunService.Heartbeat:Connect(function()
        local p = fill.Size.X.Scale
        pct.Text = math.floor(p * 100 + 0.5) .. "%"
        headGlow.Position = UDim2.new(0, 24 + (W - 48) * p - 3, 1, -27)
    end))

    for i = 1, #steps do
        task.delay(D * (i - 1) / #steps, function()
            if not card.Parent then return end
            if i > 1 then setStep(i - 1, "done") end
            setStep(i, "active")
        end)
    end

    task.delay(D + 0.1, function()
        if not card.Parent then return end
        conn:Disconnect()
        for i = 1, #steps do setStep(i, "done") end
        pct.Text = "100%"
        task.wait(0.3)
        Tween(scale, { Scale = target * 0.9 }, 0.2)
        task.wait(0.2)
        pcall(function() gui:Destroy() end)
        if onDone and Alive then onDone() end
    end)
end

----------------------------------------------------------------------------------------------------
-- Main hub
----------------------------------------------------------------------------------------------------

local Listening, ConsumedAt = false, 0
local StartedAt = Clock()

----------------------------------------------------------------------------------------------------
-- Misc: Magic Carpet (LocalPlayer's own character only, purely client-side visuals + own physics)
----------------------------------------------------------------------------------------------------

local Carpet = { Enabled = false, Speed = 50, Rainbow = false, Key = "F", OnChanged = nil }
local CarpetSession -- table holding every instance / connection / saved joint of the active flight

local CARPET_RED  = { Color3.fromRGB(150, 24, 32), Color3.fromRGB(176, 36, 40) }
local CARPET_GOLD = Color3.fromRGB(232, 182, 72)
local HUGE = 1e7

local function SafeNew(class, props)
    local ok, obj = pcall(function()
        local o = Instance.new(class)
        for k, v in pairs(props or {}) do
            if k ~= "Parent" then o[k] = v end
        end
        if props and props.Parent then o.Parent = props.Parent end
        return o
    end)
    return ok and obj or nil
end

-- seated cross-legged offsets, multiplied onto each joint's original C0
local function PoseOffsets(rigR15)
    if rigR15 then
        return {
            LeftHip    = CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, math.rad(-35), 0),
            RightHip   = CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, math.rad(35), 0),
            LeftKnee   = CFrame.Angles(math.rad(-105), 0, 0) * CFrame.Angles(0, math.rad(55), 0),
            RightKnee  = CFrame.Angles(math.rad(-105), 0, 0) * CFrame.Angles(0, math.rad(-55), 0),
        }
    end
    return {
        ["Left Hip"]  = CFrame.Angles(0, 0, math.rad(-90)) * CFrame.Angles(math.rad(35), 0, 0),
        ["Right Hip"] = CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(35), 0, 0),
    }
end

local function CarpetStop(reason)
    local s = CarpetSession
    CarpetSession = nil
    local was = Carpet.Enabled
    Carpet.Enabled = false
    if s then
        for _, c in ipairs(s.conns) do pcall(function() c:Disconnect() end) end
        for _, o in ipairs(s.objects) do pcall(function() o:Destroy() end) end
        for motor, saved in pairs(s.joints) do
            pcall(function()
                motor.C0 = saved.C0
                motor.C1 = saved.C1
            end)
        end
        pcall(function()
            if s.hum and s.hum.Parent then s.hum.PlatformStand = false end
        end)
        pcall(function()
            if s.root and s.root.Parent then
                s.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                s.root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
        end)
    end
    if was and Carpet.OnChanged then pcall(Carpet.OnChanged, false, reason) end
end

local function CarpetStart()
    if CarpetSession then return true end
    local char
    pcall(function() char = LocalPlayer.Character end)
    if not char then pcall(function() char = LocalPlayer.Character or nil end) end
    if typeof(char) ~= "Instance" then
        return false, "Character not ready"
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then
        return false, "Character not ready"
    end
    local health = 100
    pcall(function() health = hum.Health end)
    if health <= 0 then
        return false, "Character not ready"
    end
    local s = { conns = {}, objects = {}, joints = {}, hum = hum, root = root, char = char }
    CarpetSession = s
    Carpet.Enabled = true

    local ok, err = pcall(function()
        hum.PlatformStand = true

        -- pose: rotate hip / knee Motor6Ds, saving the originals
        local r15 = hum.RigType == Enum.HumanoidRigType.R15
        local offsets = PoseOffsets(r15)
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Motor6D") and offsets[d.Name] then
                s.joints[d] = { C0 = d.C0, C1 = d.C1 }
                d.C0 = d.C0 * offsets[d.Name]
            end
        end

        -- carpet: 5 cross strips (6 x 0.2 x 0.8 each => 6 x 0.2 x 4) with gold neon fringes
        local drop = r15 and -(hum.HipHeight * 0.5 + 0.55) or -1.55
        local model = SafeNew("Model", { Name = "SOLHub_Carpet" })
        s.objects[#s.objects + 1] = model
        s.strips = {}
        for i = 1, 5 do
            local z = (i - 3) * 0.8
            local strip = SafeNew("Part", {
                Name = "Strip" .. i, Size = Vector3.new(6, 0.2, 0.8),
                Color = CARPET_RED[(i % 2) + 1], Material = Enum.Material.Fabric,
                CanCollide = false, CanTouch = false, CanQuery = false, Massless = true,
                Anchored = false, CastShadow = false, Parent = model,
            })
            if strip then
                local base = CFrame.new(0, drop, z)
                local weld = SafeNew("Weld", { Part0 = root, Part1 = strip, C0 = base, Parent = strip })
                local fringes = {}
                for _, side in ipairs({ -1, 1 }) do
                    local f = SafeNew("Part", {
                        Name = "Fringe", Size = Vector3.new(0.18, 0.22, 0.8),
                        Color = CARPET_GOLD, Material = Enum.Material.Neon,
                        CanCollide = false, CanTouch = false, CanQuery = false, Massless = true,
                        CastShadow = false, Parent = model,
                    })
                    if f then
                        SafeNew("Weld", { Part0 = strip, Part1 = f, C0 = CFrame.new(side * 3.05, 0, 0), Parent = f })
                        fringes[#fringes + 1] = f
                    end
                end
                s.strips[i] = { part = strip, weld = weld, base = base, fringes = fringes }
            end
        end
        model.Parent = char

        -- movers: LinearVelocity + AlignOrientation, falling back to BodyVelocity / BodyGyro
        local att = SafeNew("Attachment", { Name = "SOLHub_CarpetAtt", Parent = root })
        if att then s.objects[#s.objects + 1] = att end
        local lv = att and SafeNew("LinearVelocity", {
            Attachment0 = att, MaxForce = HUGE, VectorVelocity = Vector3.new(0, 0, 0),
            RelativeTo = Enum.ActuatorRelativeTo.World, Parent = root,
        })
        if lv then
            s.objects[#s.objects + 1] = lv
            s.setVel = function(v) lv.VectorVelocity = v end
        else
            local bv = SafeNew("BodyVelocity", { MaxForce = Vector3.new(HUGE, HUGE, HUGE), Velocity = Vector3.new(0, 0, 0), P = 1250, Parent = root })
            if bv then
                s.objects[#s.objects + 1] = bv
                s.setVel = function(v) bv.Velocity = v end
            else
                s.setVel = function(v) root.AssemblyLinearVelocity = v end
            end
        end
        local ao = att and SafeNew("AlignOrientation", {
            Attachment0 = att, Mode = Enum.OrientationAlignmentMode.OneAttachment,
            MaxTorque = HUGE, Responsiveness = 35, RigidityEnabled = false, CFrame = root.CFrame, Parent = root,
        })
        if ao then
            s.objects[#s.objects + 1] = ao
            s.setRot = function(cf) ao.CFrame = cf end
        else
            local bg = SafeNew("BodyGyro", { MaxTorque = Vector3.new(HUGE, HUGE, HUGE), P = 9000, D = 500, CFrame = root.CFrame, Parent = root })
            if bg then
                s.objects[#s.objects + 1] = bg
                s.setRot = function(cf) bg.CFrame = cf end
            else
                s.setRot = function() end
            end
        end
    end)
    if not ok then
        CarpetStop()
        return false, "Setup failed: " .. tostring(err)
    end

    local K = {
        W = KeyCodeFrom("W"), A = KeyCodeFrom("A"), S = KeyCodeFrom("S"), D = KeyCodeFrom("D"),
        Up = KeyCodeFrom("Space"), Down = KeyCodeFrom("LeftControl"),
    }
    local function down(kc)
        if not kc then return false end
        local okd, r = pcall(function() return UserInputService:IsKeyDown(kc) end)
        return okd and r == true
    end
    local vel = Vector3.new(0, 0, 0)
    local lastYaw, bank = nil, 0

    s.conns[#s.conns + 1] = RunService.RenderStepped:Connect(function(dt)
        if CarpetSession ~= s or not Alive then return end
        local okStep, stepErr = pcall(function()
            if not root.Parent or hum.Health <= 0 then CarpetStop("died"); return end
            hum.PlatformStand = true
            local t = tick()
            local cam = Workspace.CurrentCamera
            local camCF = cam and cam.CFrame or root.CFrame
            local look = camCF.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
            local right = Vector3.new(-flat.Z, 0, flat.X)

            local typing = false
            pcall(function() typing = UserInputService:GetFocusedTextBox() ~= nil end)
            local move = Vector3.new(0, 0, 0)
            if not typing then
                if down(K.W) then move = move + look end
                if down(K.S) then move = move - look end
                if down(K.D) then move = move + right end
                if down(K.A) then move = move - right end
            end
            if move.Magnitude < 1e-3 then
                -- touch thumbstick / gamepad: Humanoid.MoveDirection, pitched by the camera
                local md = hum.MoveDirection
                if md.Magnitude > 1e-3 then
                    move = md + Vector3.new(0, look.Y * md:Dot(flat), 0)
                end
            end
            if not typing then
                if down(K.Up) then move = move + Vector3.new(0, 1, 0) end
                if down(K.Down) then move = move - Vector3.new(0, 1, 0) end
            end
            local target = (move.Magnitude > 1e-3 and move.Unit * Carpet.Speed or Vector3.new(0, 0, 0))
                + Vector3.new(0, math.sin(t * 2.2) * 0.9, 0)
            vel = vel:Lerp(target, math.clamp(dt * 6, 0, 1))
            s.setVel(vel)

            -- face camera yaw, bank into turns, slight nose-down when moving fast
            local yaw = math.atan2(-flat.X, -flat.Z)
            local dyaw = 0
            if lastYaw then
                dyaw = yaw - lastYaw
                if dyaw > math.pi then dyaw = dyaw - 2 * math.pi elseif dyaw < -math.pi then dyaw = dyaw + 2 * math.pi end
            end
            lastYaw = yaw
            local want = math.clamp(dyaw / math.max(dt, 1e-3) * 0.12, -0.45, 0.45)
            bank = bank + (want - bank) * math.clamp(dt * 5, 0, 1)
            local fwd = vel:Dot(flat) / math.max(Carpet.Speed, 1)
            s.setRot(CFrame.Angles(0, yaw, 0) * CFrame.Angles(-0.08 * fwd + math.sin(t * 1.7) * 0.02, 0, bank))

            -- undulating strips (phase-shifted sine wave) + rainbow
            for i, st in pairs(s.strips) do
                local wave = math.sin(t * 4 - i * 0.9)
                st.weld.C0 = st.base * CFrame.new(0, wave * 0.12, 0) * CFrame.Angles(wave * 0.08, 0, 0)
                if Carpet.Rainbow then
                    st.part.Color = Color3.fromHSV((t * 0.25 + i * 0.08) % 1, 0.75, 1)
                    st.part.Material = Enum.Material.Neon
                else
                    st.part.Color = CARPET_RED[(i % 2) + 1]
                    st.part.Material = Enum.Material.Fabric
                end
            end
        end)
        if not okStep then
            warn("[SOL Hub] carpet step: " .. tostring(stepErr))
            CarpetStop("error")
        end
    end)
    do
        local okDied, died = pcall(function() return hum.Died end)
        if okDied and died then
            s.conns[#s.conns + 1] = died:Connect(function() CarpetStop("died") end)
        end
    end
    do
        local okAdd, sig = pcall(function() return LocalPlayer.CharacterAdded end)
        if okAdd and sig then
            s.conns[#s.conns + 1] = sig:Connect(function() CarpetStop("respawn") end)
        end
    end
    s.conns[#s.conns + 1] = char.AncestryChanged:Connect(function(_, parent)
        if not parent then CarpetStop("respawn") end
    end)
    return true
end

local function CarpetSet(on)
    if on then
        local ok, why = CarpetStart()
        if not ok then
            if Carpet.OnChanged then pcall(Carpet.OnChanged, false, why) end
            return false, why
        end
        if Carpet.OnChanged then pcall(Carpet.OnChanged, true) end
        return true
    end
    CarpetStop("off")
    return true
end

-- hub unload -> land the carpet and restore everything
Track({ Destroy = function() CarpetStop("unload") end })

local function OpenHub()
    local W, H = 760, 500
    local SIDE = 200
    local HEADER = 78

    local gui = Track(MountGui("SOLHub_Main", 900))

    local Root = New("Frame", {
        Name = "Window",
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = 1,
    })
    local ShadowImg = Shadow(Root, 1)

    local Body = New("Frame", { Parent = Root, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { BackgroundColor3 = "Background" })
    Round(Body, 16)
    Rim(Body, "StrokeHover", 0.05, 0.7)

    -- soft accent glow across the top of the window
    local Glow = New("Frame", { Parent = Body, Size = UDim2.new(1, 0, 0, 200), ZIndex = 1 }, { BackgroundColor3 = "Accent" })
    Round(Glow, 16)
    Fade(Glow, 0.9, 1, 90)

    -- fade cover (replaces CanvasGroup: renders the same on every device / executor)
    local Cover = New("Frame", {
        Parent = Root, Size = UDim2.fromScale(1, 1), ZIndex = 50, BackgroundTransparency = 0,
    }, { BackgroundColor3 = "Background" })
    Round(Cover, 16)

    local scale = New("UIScale", { Scale = FitScale(W, H) * 0.9, Parent = Root })
    local target = FitScale(W, H)
    Tween(scale, { Scale = target }, 0.5, Enum.EasingStyle.Back)
    Tween(Cover, { BackgroundTransparency = 1 }, 0.35)
    Tween(ShadowImg, { ImageTransparency = 0.45 }, 0.4)
    task.delay(0.36, function() if Cover.BackgroundTransparency > 0.99 then Cover.Visible = false end end)

    ------------------------------------------------------------------ sidebar
    local Side = New("Frame", {
        Parent = Body,
        Size = UDim2.new(0, SIDE, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
    })
    local SideFill = New("Frame", {
        Parent = Side,
        Size = UDim2.new(1, 24, 1, 0),
        ZIndex = 2,
    }, { BackgroundColor3 = "Surface" })
    Round(SideFill, 16)
    Shade(SideFill, 0.82, 90)
    local SideLine = New("Frame", {
        Parent = Side,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = SideLine, Rotation = 90, Transparency = Stops({ { 0, 0.6 }, { 0.15, 0 }, { 0.85, 0 }, { 1, 0.6 } }) })

    local SideHeader = New("Frame", {
        Parent = Side,
        Size = UDim2.new(1, 0, 0, 72),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    Logo(SideHeader, UDim2.fromOffset(18, 18), 38, 11, 20, 3, 2.1)
    Label(SideHeader, Config.HubName, 16, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(68, 18),
        Size = UDim2.new(1, -78, 0, 18),
        ZIndex = 4,
    })
    local VerBadge = New("Frame", {
        Parent = SideHeader,
        Position = UDim2.fromOffset(68, 39),
        Size = UDim2.fromOffset(0, 17),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 0.86,
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(VerBadge, "full")
    Outline(VerBadge, "Accent", 1, 0.7)
    New("UIPadding", { Parent = VerBadge, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
    Label(VerBadge, Config.Version, 10, "Accent", Enum.Font.GothamBold, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, ZIndex = 5,
    })

    Label(Side, "MENU", 10, "Muted", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(22, 82),
        Size = UDim2.new(1, -40, 0, 14),
        ZIndex = 3,
    })

    local TabArea = New("Frame", {
        Parent = Side,
        Position = UDim2.fromOffset(0, 102),
        Size = UDim2.new(1, 0, 1, -(102 + 84)),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    local Indicator = New("Frame", {
        Parent = TabArea,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 0, 38),
        BackgroundTransparency = 0.25,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface3" })
    Round(Indicator, 10)
    Rim(Indicator, "StrokeHover", 0.2, 0.8)
    local IndicatorGlow = New("Frame", {
        Parent = Indicator, Size = UDim2.fromScale(1, 1), ZIndex = 3,
    }, { BackgroundColor3 = "Accent" })
    Round(IndicatorGlow, 10)
    Fade(IndicatorGlow, 0.8, 1, 0)
    SoftGlow(Indicator, "Accent", UDim2.new(0, 2, 0.5, 0), UDim2.fromOffset(46, 46), 0.72, 3)
    local IndicatorBar = New("Frame", {
        Parent = Indicator,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 18),
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(IndicatorBar, "full")

    local TabStack = New("Frame", {
        Parent = TabArea,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 5,
    })
    New("UIListLayout", { Parent = TabStack, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })

    local Profile = New("Frame", {
        Parent = Side,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 10, 1, -10),
        Size = UDim2.new(1, -20, 0, 62),
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(Profile, 12)
    Rim(Profile, "StrokeHover", 0.25, 0.85)
    local ProfileTint = New("Frame", { Parent = Profile, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { BackgroundColor3 = "Accent" })
    Round(ProfileTint, 12)
    Fade(ProfileTint, 0.9, 1, 0)
    local Avatar = New("ImageLabel", {
        Parent = Profile,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(38, 38),
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        ZIndex = 4,
    }, { BackgroundColor3 = "Surface3" })
    Avatar.BackgroundTransparency = 0
    Round(Avatar, "full")
    Outline(Avatar, "Accent", 1.5, 0.25)
    SoftGlow(Profile, "Accent", UDim2.new(0, 31, 0.5, 0), UDim2.fromOffset(64, 64), 0.75, 3)
    Label(Profile, LocalPlayer.DisplayName, 13, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(60, 13),
        Size = UDim2.new(1, -70, 0, 16),
        ZIndex = 4,
    })
    local Dot = New("Frame", {
        Parent = Profile,
        Position = UDim2.fromOffset(61, 37),
        Size = UDim2.fromOffset(6, 6),
        ZIndex = 4,
    }, { BackgroundColor3 = "Success" })
    Round(Dot, "full")
    Outline(Dot, "Success", 3, 0.8)
    Label(Profile, "Key active", 11, "Muted", nil, {
        Position = UDim2.fromOffset(73, 32),
        Size = UDim2.new(1, -83, 0, 16),
        ZIndex = 4,
    })

    ------------------------------------------------------------------ content / header
    local Content = New("Frame", {
        Parent = Body,
        Position = UDim2.fromOffset(SIDE + 1, 0),
        Size = UDim2.new(1, -(SIDE + 1), 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
    })

    local Header = New("Frame", {
        Parent = Content,
        Size = UDim2.new(1, 0, 0, HEADER),
        BackgroundTransparency = 1,
        ZIndex = 2,
    })
    local PageTitle = Label(Header, "", 23, "Text", Enum.Font.GothamBlack, {
        Position = UDim2.fromOffset(26, 17),
        Size = UDim2.new(1, -340, 0, 28),
        ZIndex = 3,
    })
    local PageDesc = Label(Header, "", 12, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(26, 47),
        Size = UDim2.new(1, -340, 0, 16),
        ZIndex = 3,
    })
    local HeaderLine = New("Frame", {
        Parent = Header,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 26, 1, 0),
        Size = UDim2.new(1, -52, 0, 1),
        ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", {
        Parent = HeaderLine,
        Transparency = Stops({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
    })
    -- short accent underline under the page title
    local TitleBar = New("Frame", {
        Parent = Header,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 26, 1, 0),
        Size = UDim2.fromOffset(36, 2),
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(TitleBar, "full")
    SoftGlow(Header, "Accent", UDim2.new(0, 44, 1, -1), UDim2.fromOffset(70, 26), 0.82, 3)

    local SearchWrap = New("Frame", {
        Parent = Header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -98, 0, 22),
        Size = UDim2.fromOffset(210, 32),
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(SearchWrap, 10)
    local SearchStroke = Rim(SearchWrap, "StrokeHover", 0.3, 0.85)
    local SearchIcon = Icon(SearchWrap, "search", 14, "Muted", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 11, 0.5, 0),
        ZIndex = 4,
    })
    local SearchBox = New("TextBox", {
        Parent = SearchWrap,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(33, 0),
        Size = UDim2.new(1, -43, 1, 0),
        Text = "",
        PlaceholderText = "Search games...",
        TextSize = 13,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 4,
    }, { TextColor3 = "Text", PlaceholderColor3 = "Muted" })
    SearchBox.Focused:Connect(function()
        Bind(SearchStroke, "Color", "Accent", 0.15)
        Bind(SearchIcon, "ImageColor3", "Accent", 0.15)
    end)
    SearchBox.FocusLost:Connect(function()
        Bind(SearchStroke, "Color", "StrokeHover", 0.2)
        Bind(SearchIcon, "ImageColor3", "Muted", 0.2)
    end)

    local Pages = New("Frame", {
        Parent = Content,
        Position = UDim2.fromOffset(0, HEADER),
        Size = UDim2.new(1, 0, 1, -HEADER),
        BackgroundTransparency = 1,
        ZIndex = 2,
    })

    local function NewPage()
        local sc = New("ScrollingFrame", {
            Parent = Pages,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ScrollBarThickness = 3,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            ZIndex = 2,
        }, { ScrollBarImageColor3 = "Accent" })
        New("UIPadding", {
            Parent = sc, PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26),
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 22),
        })
        New("UIListLayout", { Parent = sc, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) })
        return sc
    end

    local function SectionHeader(parent, title, order)
        local row = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
            ZIndex = 2,
        })
        local mark = New("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(3, 14),
            ZIndex = 3,
        }, { BackgroundColor3 = "Accent" })
        Round(mark, "full")
        Label(row, title, 14, "Text", Enum.Font.GothamBold, {
            Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(1, -132, 1, 0), ZIndex = 3,
        })
        local pill = New("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface2" })
        Round(pill, "full")
        Rim(pill, "StrokeHover", 0.3, 0.85)
        New("UIPadding", { Parent = pill, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
        local txt = Label(pill, "", 11, "Muted", Enum.Font.GothamMedium, {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            TextTruncate = Enum.TextTruncate.None, ZIndex = 4,
        })
        return function(t) txt.Text = t end
    end

    local function Columns(parent, order)
        local holder = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
            ZIndex = 2,
        })
        New("UIListLayout", {
            Parent = holder,
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12),
        })
        local function col(i)
            local f = New("Frame", {
                Parent = holder,
                Size = UDim2.new(0.5, -6, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = i,
                ZIndex = 2,
            })
            New("UIListLayout", { Parent = f, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) })
            return f
        end
        return col(1), col(2)
    end

    local function Groupbox(parent, o)
        local box = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = o.Order or 0,
            ZIndex = 2,
        }, { BackgroundColor3 = "Surface2" })
        Round(box, 12)
        Rim(box, "StrokeHover", 0.2, 0.85)
        New("UIListLayout", { Parent = box, SortOrder = Enum.SortOrder.LayoutOrder })

        local header = New("TextButton", {
            Parent = box,
            Size = UDim2.new(1, 0, 0, 44),
            Text = "",
            BackgroundTransparency = 1,
            LayoutOrder = 1,
            ZIndex = 3,
        })
        local tile = New("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.fromOffset(28, 28),
            BackgroundTransparency = 0.86,
            ZIndex = 3,
        }, { BackgroundColor3 = "Accent" })
        Round(tile, 8)
        Outline(tile, "Accent", 1, 0.75)
        Icon(tile, o.Icon or "info", 14, "Accent", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            ZIndex = 4,
        })
        Label(header, o.Name, 13, "Text", Enum.Font.GothamBold, {
            Position = UDim2.fromOffset(50, 0),
            Size = UDim2.new(1, -(50 + 110), 1, 0),
            ZIndex = 4,
        })
        local right = Label(header, "", 11, "Muted", nil, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -38, 0.5, 0),
            Size = UDim2.fromOffset(90, 16),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 4,
        })
        local chev = Icon(header, "chevron-down", 14, "Muted", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            ZIndex = 4,
        })

        local divider = New("Frame", {
            Parent = box,
            Size = UDim2.new(1, 0, 0, 1),
            LayoutOrder = 2,
            ZIndex = 3,
        }, { BackgroundColor3 = "Stroke" })
        New("UIGradient", { Parent = divider, Transparency = Stops({ { 0, 1 }, { 0.12, 0 }, { 0.88, 0 }, { 1, 1 } }) })

        local body = New("Frame", {
            Parent = box,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 3,
            ZIndex = 3,
        })
        New("UIPadding", {
            Parent = body, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8),
        })
        New("UIListLayout", { Parent = body, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })

        local collapsed = false
        header.MouseEnter:Connect(function() Bind(chev, "ImageColor3", "Text", 0.15) end)
        header.MouseLeave:Connect(function() Bind(chev, "ImageColor3", "Muted", 0.25) end)
        header.MouseButton1Click:Connect(function()
            collapsed = not collapsed
            body.Visible = not collapsed
            divider.Visible = not collapsed
            Tween(chev, { Rotation = collapsed and -90 or 0 }, 0.25)
        end)

        return body, function(text) right.Text = text end
    end

    local function ToggleRow(parent, o)
        local h = o.Desc and 46 or 34
        local row = New("TextButton", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, h),
            Text = "",
            BackgroundTransparency = 1,
            LayoutOrder = o.Order or 0,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface3" })
        Round(row, 8)
        Label(row, o.Name, 13, "Text", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(10, o.Desc and 7 or 0),
            Size = UDim2.new(1, -72, 0, o.Desc and 18 or h),
            ZIndex = 4,
        })
        if o.Desc then
            Label(row, o.Desc, 11, "Muted", nil, {
                Position = UDim2.fromOffset(10, 25),
                Size = UDim2.new(1, -72, 0, 14),
                ZIndex = 4,
            })
        end
        local value = o.Default == true
        local track = New("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(38, 22),
            ZIndex = 4,
        }, { BackgroundColor3 = value and "Accent" or "Surface3" })
        Round(track, "full")
        Shade(track, 0.8, 90)
        local trackStroke = Outline(track, value and "Accent" or "Stroke")
        local knob = New("Frame", {
            Parent = track,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            ZIndex = 5,
        }, { BackgroundColor3 = value and "AccentDark" or "Muted" })
        Round(knob, "full")

        local obj = {}
        function obj:Set(v, silent)
            v = v == true
            if v == value then return end
            value = v
            Bind(track, "BackgroundColor3", value and "Accent" or "Surface3", 0.2)
            Bind(trackStroke, "Color", value and "Accent" or "Stroke", 0.2)
            Bind(knob, "BackgroundColor3", value and "AccentDark" or "Muted", 0.2)
            Tween(knob, { Position = value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.25, Enum.EasingStyle.Back)
            if not silent and o.Callback then task.spawn(o.Callback, value) end
        end
        function obj:Get() return value end

        row.MouseEnter:Connect(function() Tween(row, { BackgroundTransparency = 0.6 }, 0.12) end)
        row.MouseLeave:Connect(function() Tween(row, { BackgroundTransparency = 1 }, 0.2) end)
        row.MouseButton1Click:Connect(function() obj:Set(not value) end)
        return obj
    end

    local function StatRow(parent, name, value, order)
        local row = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = order or 0,
            ZIndex = 3,
        })
        Label(row, name, 12, "Muted", nil, {
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(0.4, 0, 1, 0),
            ZIndex = 4,
        })
        return Label(row, value, 12, "Text", Enum.Font.GothamMedium, {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -10, 0, 0),
            Size = UDim2.new(0.6, -20, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 4,
        })
    end

    local function ButtonRow(parent, o)
        local row = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
            LayoutOrder = o.Order or 0,
            ZIndex = 3,
        })
        return Chip({
            Parent = row,
            Position = UDim2.fromOffset(4, 3),
            Size = UDim2.new(1, -8, 0, 34),
            Text = o.Text, Icon = o.Icon, Style = o.Style, Callback = o.Callback, ZIndex = 4,
        })
    end

    local function SliderRow(parent, o)
        local min, max = o.Min or 0, o.Max or 100
        local value = math.clamp(o.Default or min, min, max)
        local row = New("Frame", {
            Parent = parent, Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1,
            LayoutOrder = o.Order or 0, ZIndex = 3,
        })
        Label(row, o.Name, 13, "Text", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -80, 0, 18), ZIndex = 4,
        })
        local valueLbl = Label(row, "", 12, "Accent", Enum.Font.GothamBold, {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(70, 18),
            TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4,
        })
        local track = New("TextButton", {
            Parent = row, Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -20, 0, 6),
            Text = "", AutoButtonColor = false, ZIndex = 4,
        }, { BackgroundColor3 = "Surface3" })
        Round(track, "full")
        Outline(track, "Stroke")
        local fill = New("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), ZIndex = 5 }, { BackgroundColor3 = "Accent" })
        Round(fill, "full")
        Shade(fill, 0.8, 0)
        local knob = New("Frame", {
            Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(14, 14), ZIndex = 6,
        }, { BackgroundColor3 = "Text" })
        Round(knob, "full")
        Outline(knob, "Accent", 2)

        local obj = {}
        local function render()
            local a = (max > min) and (value - min) / (max - min) or 0
            fill.Size = UDim2.fromScale(a, 1)
            knob.Position = UDim2.fromScale(a, 0.5)
            valueLbl.Text = tostring(value) .. (o.Suffix or "")
        end
        function obj:Set(v, silent)
            v = math.clamp(math.floor((tonumber(v) or min) + 0.5), min, max)
            if v == value then render(); return end
            value = v
            render()
            if not silent and o.Callback then task.spawn(o.Callback, value) end
        end
        function obj:Get() return value end
        render()

        local dragging = false
        local function fromX(x)
            local w = track.AbsoluteSize.X
            if w < 1 then return end
            obj:Set(min + (max - min) * math.clamp((x - track.AbsolutePosition.X) / w, 0, 1))
        end
        track.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                dragging = true
                if input.Position then fromX(input.Position.X) end
            end
        end)
        Track(UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then fromX(input.Position.X) end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then dragging = false end
        end))
        return obj
    end

    -- key chip in the same style as the Settings "Show / hide" binder
    local function KeybindRow(parent, o)
        local key = o.Default
        local row = New("Frame", {
            Parent = parent, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = o.Order or 0, ZIndex = 3,
        })
        Label(row, o.Name, 13, "Text", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 4,
        })
        local chip = New("TextButton", {
            Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(92, 24), Text = key, TextSize = 12, Font = Enum.Font.GothamBold, ZIndex = 4,
        }, { BackgroundColor3 = "Background", TextColor3 = "Muted" })
        Round(chip, 8)
        local chipStroke = Rim(chip, "StrokeHover", 0.25, 0.8)
        Pressable(chip, 0.94)
        chip.MouseButton1Click:Connect(function()
            if Listening then return end
            if IsTouchOnly() then
                Notify("No keyboard", "Use the toggle on mobile", "info")
                return
            end
            Listening = true
            chip.Text = "Press a key"
            Bind(chipStroke, "Color", "Accent", 0.15)
            Bind(chip, "TextColor3", "Accent", 0.15)
            local c
            c = Track(UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                c:Disconnect()
                ConsumedAt = Clock()
                if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
                    key = input.KeyCode.Name
                    if o.Callback then task.spawn(o.Callback, key) end
                end
                chip.Text = key
                Bind(chipStroke, "Color", "StrokeHover", 0.2)
                Bind(chip, "TextColor3", "Muted", 0.2)
                task.defer(function() Listening = false end)
            end))
        end)
        return function() return key end
    end

    -- shared launcher used by game cards and quick-launch rows
    local function Launch(g, runLabel)
        local ok, err = RunGame(g)
        if runLabel and runLabel.Parent then runLabel.Text = "Run" end
        if ok then
            Notify(g.Name, "Script launched successfully", "success")
        else
            Notify("Error: " .. g.Name, string.sub(tostring(err), 1, 80), "error", 5)
        end
    end

    local function RunButton(parent, g, size, zi, inset)
        inset = inset or 10
        local busy = false
        local runLabel
        local _
        _, runLabel = Chip({
            Parent = parent,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -inset, 1, -inset),
            Size = size or UDim2.fromOffset(78, 28),
            Text = "Run", Icon = "play", Style = "primary", TextSize = 12, IconSize = 12, ZIndex = zi or 4,
            Callback = function()
                if busy then return end
                busy = true
                runLabel.Text = "..."
                Launch(g, runLabel)
                busy = false
            end,
        })
        return runLabel
    end

    -- tinted game tile: per-game colour, shaded, glossy top, lit rim, white initial
    local function Monogram(parent, name, size, textSize, pos, anchor, zi, tint)
        local tile = New("Frame", {
            Parent = parent,
            AnchorPoint = anchor or Vector2.new(0, 0),
            Position = pos,
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = tint,
            ZIndex = zi,
        })
        local r = math.floor(size * 0.3)
        Round(tile, r)
        Shade(tile, 0.5, 50)
        local rim = New("UIStroke", { Parent = tile, Color = Color3.new(1, 1, 1), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        New("UIGradient", { Parent = rim, Rotation = 90, Transparency = NumberSequence.new(0.55, 1) })
        local gloss = New("Frame", {
            Parent = tile, Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = zi,
        })
        Round(gloss, r)
        Fade(gloss, 0.8, 1, 90)
        local letter = Label(tile, string.upper(string.sub(name, 1, 1)), textSize, "Text", Enum.Font.GothamBlack, {
            Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            ZIndex = zi + 1,
        })
        return tile, letter
    end

    -- game tile for the grid
    local function GameCard(parent, g, i)
        local tint = TintFor(i)
        local card = New("Frame", {
            Parent = parent,
            LayoutOrder = i,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface2" })
        Round(card, 14)
        local stroke = Rim(card, "StrokeHover", 0.15, 0.8)

        local banner = New("Frame", {
            Parent = card,
            Position = UDim2.fromOffset(6, 6),
            Size = UDim2.new(1, -12, 0, 70),
            ClipsDescendants = true,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface3" })
        Round(banner, 10)
        -- per-game colour wash (strong on the left, fading to the right)
        local wash = New("Frame", {
            Parent = banner, Size = UDim2.fromScale(1, 1), BackgroundColor3 = tint, BackgroundTransparency = 0.25, ZIndex = 3,
        })
        Round(wash, 10)
        New("UIGradient", { Parent = wash, Rotation = 20, Transparency = Stops({ { 0, 0.55 }, { 0.55, 0.85 }, { 1, 0.97 } }) })
        -- soft tinted glow behind the monogram
        SoftGlow(banner, tint, UDim2.new(0, 32, 0.5, 0), UDim2.fromOffset(110, 110), 0.55, 3)
        -- concentric rings on the right
        for _, rr in ipairs({ { 60, 0.72 }, { 100, 0.82 }, { 144, 0.9 } }) do
            local ring = New("Frame", {
                Parent = banner,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(1, -36, 0.5, 0),
                Size = UDim2.fromOffset(rr[1], rr[1]),
                BackgroundTransparency = 1,
                ZIndex = 4,
            })
            Round(ring, "full")
            New("UIStroke", { Parent = ring, Color = tint, Thickness = 1, Transparency = rr[2], ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        end
        -- diagonal shine band (slides across on hover)
        local shine = New("Frame", {
            Parent = banner, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4,
        })
        Round(shine, 10)
        local shineGrad = New("UIGradient", {
            Parent = shine,
            Rotation = 25,
            Offset = Vector2.new(-0.15, 0),
            Transparency = Stops({ { 0, 1 }, { 0.42, 1 }, { 0.5, 0.9 }, { 0.54, 0.94 }, { 0.58, 1 }, { 1, 1 } }),
        })
        -- bottom fade so the banner melts into the card
        local fadeBottom = New("Frame", {
            Parent = banner, Size = UDim2.fromScale(1, 1), ZIndex = 4,
        }, { BackgroundColor3 = "Surface2" })
        Round(fadeBottom, 10)
        Fade(fadeBottom, 1, 0.55, 90)

        Monogram(banner, g.Name, 40, 18, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5), 5, tint)
        local tag = New("Frame", {
            Parent = banner,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, 8),
            Size = UDim2.fromOffset(30, 16),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.55,
            ZIndex = 5,
        })
        Round(tag, "full")
        Label(tag, string.format("#%02d", i), 10, "Text", Enum.Font.GothamBold, {
            Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            ZIndex = 6,
        })

        Label(card, g.Name, 14, "Text", Enum.Font.GothamBold, {
            Position = UDim2.fromOffset(14, 86),
            Size = UDim2.new(1, -28, 0, 18),
            ZIndex = 4,
        })
        local dot = New("Frame", {
            Parent = card,
            Position = UDim2.fromOffset(15, 115),
            Size = UDim2.fromOffset(6, 6),
            ZIndex = 4,
        }, { BackgroundColor3 = "Success" })
        Round(dot, "full")
        Outline(dot, "Success", 3, 0.82)
        Label(card, g.Desc or "Ready to run", 12, "Muted", nil, {
            Position = UDim2.fromOffset(28, 110),
            Size = UDim2.new(1, -124, 0, 16),
            ZIndex = 4,
        })
        RunButton(card, g, UDim2.fromOffset(80, 30), 5, 12)

        card.MouseEnter:Connect(function()
            Bind(stroke, "Color", "Accent", 0.15)
            Tween(wash, { BackgroundTransparency = 0 }, 0.2)
            shineGrad.Offset = Vector2.new(-0.7, 0)
            Tween(shineGrad, { Offset = Vector2.new(0.7, 0) }, 0.6, Enum.EasingStyle.Quad)
        end)
        card.MouseLeave:Connect(function()
            Bind(stroke, "Color", "StrokeHover", 0.25)
            Tween(wash, { BackgroundTransparency = 0.25 }, 0.25)
        end)
        return card
    end

    -- compact row used on the Home page
    local function GameRow(parent, g, i)
        local row = New("Frame", {
            Parent = parent,
            Size = UDim2.new(1, 0, 0, 54),
            LayoutOrder = i,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface2" })
        Round(row, 12)
        local stroke = Rim(row, "StrokeHover", 0.2, 0.85)
        local tint = TintFor(i)
        local wash = New("Frame", { Parent = row, Size = UDim2.fromScale(1, 1), BackgroundColor3 = tint, BackgroundTransparency = 0.5, ZIndex = 3 })
        Round(wash, 12)
        Fade(wash, 0.8, 1, 0)
        SoftGlow(row, tint, UDim2.new(0, 28, 0.5, 0), UDim2.fromOffset(70, 70), 0.7, 3)
        Monogram(row, g.Name, 34, 15, UDim2.new(0, 11, 0.5, 0), Vector2.new(0, 0.5), 4, tint)
        Label(row, g.Name, 13, "Text", Enum.Font.GothamBold, {
            Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -160, 0, 17), ZIndex = 4,
        })
        Label(row, g.Desc or "Ready to run", 11, "Muted", nil, {
            Position = UDim2.fromOffset(58, 28), Size = UDim2.new(1, -160, 0, 14), ZIndex = 4,
        })
        RunButton(row, g, UDim2.fromOffset(74, 30), 5, 12)
        row.MouseEnter:Connect(function()
            Bind(stroke, "Color", "Accent", 0.15)
            Tween(wash, { BackgroundTransparency = 0 }, 0.2)
        end)
        row.MouseLeave:Connect(function()
            Bind(stroke, "Color", "StrokeHover", 0.25)
            Tween(wash, { BackgroundTransparency = 0.5 }, 0.25)
        end)
        return row
    end

    ------------------------------------------------------------------ pages
    local SelectTab -- forward
    local HeroHint

    -- HOME
    local HomePage = NewPage()
    do
        local hero = New("Frame", {
            Parent = HomePage,
            Size = UDim2.new(1, 0, 0, 124),
            LayoutOrder = 1,
            ClipsDescendants = true,
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface2" })
        Round(hero, 16)
        Rim(hero, "Accent", 0.45, 0.9)
        -- layered accent wash: diagonal gradient + a soft bloom in the top-right corner
        local heroGlow = New("Frame", { Parent = hero, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { BackgroundColor3 = "Accent" })
        Round(heroGlow, 16)
        New("UIGradient", { Parent = heroGlow, Rotation = 15, Transparency = Stops({ { 0, 0.74 }, { 0.5, 0.9 }, { 1, 0.97 } }) })
        SoftGlow(hero, "Accent", UDim2.new(1, -70, 0, 0), UDim2.fromOffset(300, 220), 0.8, 3)
        for _, r in ipairs({ { 120, 0.78 }, { 190, 0.86 }, { 270, 0.92 } }) do
            local ring = New("Frame", {
                Parent = hero,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(1, -70, 0, 6),
                Size = UDim2.fromOffset(r[1], r[1]),
                BackgroundTransparency = 1,
                ZIndex = 3,
            })
            Round(ring, "full")
            Outline(ring, "Accent", 1, r[2])
        end
        local heroShine = New("Frame", { Parent = hero, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
        Round(heroShine, 16)
        New("UIGradient", { Parent = heroShine, Rotation = 90, Transparency = NumberSequence.new(0.95, 1) })

        -- small "WELCOME BACK" eyebrow pill
        local eyebrow = New("Frame", {
            Parent = hero,
            Position = UDim2.fromOffset(22, 20),
            Size = UDim2.fromOffset(0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0.84,
            ZIndex = 4,
        }, { BackgroundColor3 = "Accent" })
        Round(eyebrow, "full")
        Outline(eyebrow, "Accent", 1, 0.7)
        New("UIPadding", { Parent = eyebrow, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9) })
        New("UIListLayout", {
            Parent = eyebrow, FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        })
        local eDot = New("Frame", { Parent = eyebrow, Size = UDim2.fromOffset(5, 5), LayoutOrder = 1, ZIndex = 5 }, { BackgroundColor3 = "Accent" })
        Round(eDot, "full")
        Label(eyebrow, "WELCOME BACK", 9, "Accent", Enum.Font.GothamBold, {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 5,
        })
        Label(hero, "Hey, " .. LocalPlayer.DisplayName, 24, "Text", Enum.Font.GothamBlack, {
            Position = UDim2.fromOffset(22, 46), Size = UDim2.new(1, -200, 0, 28), ZIndex = 4,
        })
        local hint = IsTouchOnly() and "Use the minimize button to tuck the hub away"
            or ("Press " .. State.ToggleKey .. " to show / hide the hub")
        HeroHint = Label(hero, #Games .. " scripts ready  -  " .. hint, 12, "Muted", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(22, 80), Size = UDim2.new(1, -200, 0, 32),
            TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4,
        })
        SoftGlow(hero, "Accent", UDim2.new(1, -92, 0.5, 6), UDim2.fromOffset(190, 80), 0.72, 3)
        Chip({
            Parent = hero,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -22, 0.5, 0),
            Size = UDim2.fromOffset(142, 38),
            Text = "Browse games", Icon = "layout-grid", Style = "primary", TextSize = 13, Radius = 10, ZIndex = 4,
            Callback = function() if SelectTab then SelectTab("Games") end end,
        })

        local stats = New("Frame", {
            Parent = HomePage,
            Size = UDim2.new(1, 0, 0, 74),
            BackgroundTransparency = 1,
            LayoutOrder = 2,
            ZIndex = 3,
        })
        New("UIListLayout", {
            Parent = stats, FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12),
        })
        local function StatTile(order, icon, name, value)
            local t = New("Frame", {
                Parent = stats,
                Size = UDim2.new(1 / 3, -8, 1, 0),
                LayoutOrder = order,
                ClipsDescendants = true,
                ZIndex = 3,
            }, { BackgroundColor3 = "Surface2" })
            Round(t, 14)
            Rim(t, "StrokeHover", 0.15, 0.85)
            local tint = New("Frame", { Parent = t, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { BackgroundColor3 = "Accent" })
            Round(tint, 14)
            New("UIGradient", { Parent = tint, Rotation = 35, Transparency = Stops({ { 0, 0.88 }, { 0.6, 0.98 }, { 1, 1 } }) })
            SoftGlow(t, "Accent", UDim2.new(0, 31, 0.5, 0), UDim2.fromOffset(72, 72), 0.72, 3)
            local box = New("Frame", {
                Parent = t,
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 14, 0.5, 0),
                Size = UDim2.fromOffset(36, 36),
                BackgroundTransparency = 0.82,
                ZIndex = 4,
            }, { BackgroundColor3 = "Accent" })
            Round(box, 11)
            Rim(box, "Accent", 0.35, 0.85)
            Icon(box, icon, 17, "Accent", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
            })
            Label(t, name, 9, "Muted", Enum.Font.GothamBold, {
                Position = UDim2.fromOffset(62, 19), Size = UDim2.new(1, -72, 0, 12), ZIndex = 4,
            })
            return Label(t, value, 16, "Text", Enum.Font.GothamBold, {
                Position = UDim2.fromOffset(62, 34), Size = UDim2.new(1, -72, 0, 20), ZIndex = 4,
            })
        end
        StatTile(1, "layout-grid", "SCRIPTS", tostring(#Games))
        StatTile(2, "monitor", "EXECUTOR", ExecutorName())
        local SessionLabel = StatTile(3, "info", "SESSION", "00:00")
        task.spawn(function()
            while Alive and SessionLabel.Parent do
                local t = math.floor(Clock() - StartedAt)
                local h = math.floor(t / 3600)
                local m = math.floor((t % 3600) / 60)
                local s = t % 60
                SessionLabel.Text = (h > 0) and string.format("%d:%02d:%02d", h, m, s) or string.format("%02d:%02d", m, s)
                task.wait(1)
            end
        end)

        SectionHeader(HomePage, "Quick launch", 3)("Top " .. math.min(3, #Games))
        local list = New("Frame", {
            Parent = HomePage,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 4,
            ZIndex = 3,
        })
        New("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
        for i = 1, math.min(3, #Games) do GameRow(list, Games[i], i) end
    end

    -- GAMES
    local GamesPage = NewPage()
    local SetLibraryCount = SectionHeader(GamesPage, "Library", 1)
    local Grid = New("Frame", {
        Parent = GamesPage,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        ZIndex = 3,
    })
    New("UIGridLayout", {
        Parent = Grid,
        CellSize = UDim2.new(0.5, -6, 0, 144),
        CellPadding = UDim2.fromOffset(12, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local Empty = New("Frame", {
        Parent = GamesPage,
        Size = UDim2.new(1, 0, 0, 140),
        LayoutOrder = 3,
        Visible = false,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(Empty, 14)
    Rim(Empty, "StrokeHover", 0.2, 0.85)
    local emptyTile = New("Frame", {
        Parent = Empty, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24),
        Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 0.86, ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(emptyTile, 12)
    Outline(emptyTile, "Accent", 1, 0.7)
    Icon(emptyTile, "search", 18, "Accent", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
    })
    Label(Empty, "No games found", 14, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
    })
    Label(Empty, "Try another search", 12, "Muted", nil, {
        Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
    })

    local function RefreshGames(filter)
        filter = string.lower(filter or "")
        for _, child in ipairs(Grid:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        local count = 0
        for i, g in ipairs(Games) do
            if filter == "" or string.find(string.lower(g.Name), filter, 1, true) then
                count = count + 1
                GameCard(Grid, g, i)
            end
        end
        SetLibraryCount(count .. " script" .. (count > 1 and "s" or ""))
        Grid.Visible = count > 0
        Empty.Visible = count == 0
    end
    RefreshGames("")
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        RefreshGames(SearchBox.Text)
    end)

    -- SETTINGS
    local SettingsPage = NewPage()
    local Left, Right = Columns(SettingsPage, 1)

    local InterfaceBody = Groupbox(Left, { Name = "Interface", Icon = "monitor", Order = 1 })
    ToggleRow(InterfaceBody, {
        Name = "Notifications", Desc = "Show on-screen alerts", Default = State.Notifs, Order = 1,
        Callback = function(v)
            State.Notifs = v
            SaveSettings()
        end,
    })
    ToggleRow(InterfaceBody, {
        Name = "Remember key", Desc = "Auto sign-in on next launch", Default = State.RememberKey, Order = 2,
        Callback = function(v)
            State.RememberKey = v
            if not v then ForgetKey() end
            SaveSettings()
        end,
    })
    do
        local row = New("Frame", {
            Parent = InterfaceBody, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 3,
        })
        Label(row, "Show / hide", 13, "Text", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 4,
        })
        local chip = New("TextButton", {
            Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(92, 24),
            Text = State.ToggleKey,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            ZIndex = 4,
        }, { BackgroundColor3 = "Background", TextColor3 = "Muted" })
        Round(chip, 8)
        local chipStroke = Rim(chip, "StrokeHover", 0.25, 0.8)
        Pressable(chip, 0.94)
        chip.MouseButton1Click:Connect(function()
            if Listening then return end
            if IsTouchOnly() then
                Notify("No keyboard", "Use the minimize button on mobile", "info")
                return
            end
            Listening = true
            chip.Text = "Press a key"
            Bind(chipStroke, "Color", "Accent", 0.15)
            Bind(chip, "TextColor3", "Accent", 0.15)
            local c
            c = Track(UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                c:Disconnect()
                ConsumedAt = Clock()
                if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
                    State.ToggleKey = input.KeyCode.Name
                    SaveSettings()
                    local hh = HeroHint
                    if hh and hh.Parent then
                        hh.Text = #Games .. " scripts ready  -  Press " .. State.ToggleKey .. " to show / hide the hub"
                    end
                end
                chip.Text = State.ToggleKey
                Bind(chipStroke, "Color", "StrokeHover", 0.2)
                Bind(chip, "TextColor3", "Muted", 0.2)
                task.defer(function() Listening = false end)
            end))
        end)
    end

    local AccountBody = Groupbox(Left, { Name = "Account", Icon = "user", Order = 2 })
    ButtonRow(AccountBody, {
        Text = "Copy website link", Icon = "copy", Order = 1,
        Callback = function()
            if SetClipboard(Config.SiteURL) then
                Notify("Link copied", "Paste it in your browser", "success")
            else
                Notify("Copy failed", "Your executor does not support the clipboard", "error")
            end
        end,
    })

    local function GatedButton(parent, order, text, icon, confirmText, action)
        local armed = false
        local lbl
        local _
        _, lbl = ButtonRow(parent, {
            Text = text, Icon = icon, Style = "danger", Order = order,
            Callback = function()
                if armed then
                    armed = false
                    lbl.Text = text
                    action()
                    return
                end
                armed = true
                lbl.Text = confirmText
                task.delay(3, function()
                    if armed then
                        armed = false
                        if lbl.Parent then lbl.Text = text end
                    end
                end)
            end,
        })
    end

    GatedButton(AccountBody, 2, "Forget saved key", "trash-2", "Click again to confirm", function()
        ForgetKey()
        Notify("Key removed", "It will be asked again next launch", "info")
    end)
    GatedButton(AccountBody, 3, "Unload hub", "power", "Click again to confirm", function()
        env.SOLHub_Unload()
    end)

    local AppearanceBody, SetThemeName = Groupbox(Right, { Name = "Appearance", Icon = "palette", Order = 1 })
    SetThemeName(State.Theme)
    local ThemeLabel = Label(AppearanceBody, "Theme: " .. State.Theme, 13, "Text", Enum.Font.GothamMedium, {
        Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, ZIndex = 4,
    })
    New("UIPadding", { Parent = ThemeLabel, PaddingLeft = UDim.new(0, 10) })

    local SwatchHolder = New("Frame", {
        Parent = AppearanceBody,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        ZIndex = 4,
    })
    New("UIPadding", { Parent = SwatchHolder, PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) })
    New("UIGridLayout", {
        Parent = SwatchHolder,
        CellSize = UDim2.fromOffset(30, 30),
        CellPadding = UDim2.fromOffset(10, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local swatches = {}
    local function RefreshSwatches()
        for name, s in pairs(swatches) do
            local on = name == State.Theme
            s.ring.Transparency = on and 0 or 1
            s.check.ImageTransparency = on and 0 or 1
        end
    end
    for i, name in ipairs(PresetOrder) do
        local pr = Presets[name]
        local sw = New("TextButton", {
            Parent = SwatchHolder,
            Text = "",
            LayoutOrder = i,
            BackgroundColor3 = pr.Accent,
            ZIndex = 4,
        })
        Round(sw, "full")
        Shade(sw, 0.62, 45)
        Pressable(sw, 0.88)
        local ring = Outline(sw, "Text", 2)
        local check = New("ImageLabel", {
            Parent = sw,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(14, 14),
            Image = Icons.check,
            ImageColor3 = pr.AccentDark,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 5,
        })
        swatches[name] = { ring = ring, check = check }
        sw.MouseEnter:Connect(function() ThemeLabel.Text = "Theme: " .. name end)
        sw.MouseLeave:Connect(function() ThemeLabel.Text = "Theme: " .. State.Theme end)
        sw.MouseButton1Click:Connect(function()
            State.Theme = name
            ApplyTheme()
            RefreshSwatches()
            ThemeLabel.Text = "Theme: " .. name
            SetThemeName(name)
            SaveSettings()
        end)
    end
    RefreshSwatches()

    local AboutBody = Groupbox(Right, { Name = "About", Icon = "info", Order = 2 })
    StatRow(AboutBody, "Version", Config.Version, 1)
    StatRow(AboutBody, "Executor", ExecutorName(), 2)
    StatRow(AboutBody, "Player", LocalPlayer.Name, 3)
    StatRow(AboutBody, "Place ID", tostring(game.PlaceId), 4)

    -- MISC
    local MiscPage = NewPage()
    do
        local MLeft, MRight = Columns(MiscPage, 1)
        local CarpetBody, SetCarpetStatus = Groupbox(MLeft, { Name = "Flying carpet", Icon = "play", Order = 1 })
        SetCarpetStatus("Off")
        local CarpetToggle = ToggleRow(CarpetBody, {
            Name = "Magic Carpet", Desc = "Sit cross-legged and fly", Default = false, Order = 1,
            Callback = function(v) CarpetSet(v) end,
        })
        SliderRow(CarpetBody, {
            Name = "Speed", Min = 10, Max = 150, Default = Carpet.Speed, Order = 2,
            Callback = function(v) Carpet.Speed = v end,
        })
        KeybindRow(CarpetBody, {
            Name = "Toggle key", Default = Carpet.Key, Order = 3,
            Callback = function(k) Carpet.Key = k end,
        })
        ToggleRow(CarpetBody, {
            Name = "Rainbow carpet", Desc = "Cycle neon colors", Default = Carpet.Rainbow, Order = 4,
            Callback = function(v) Carpet.Rainbow = v end,
        })

        Carpet.OnChanged = function(on, reason)
            if not Alive then return end
            CarpetToggle:Set(on, true)
            SetCarpetStatus(on and "Flying" or "Off")
            if on then
                Notify("Magic Carpet", "Hold on tight!", "success")
            elseif reason == "died" or reason == "respawn" then
                Notify("Magic Carpet", "Landed (character reset)", "info")
            elseif reason and reason ~= "off" and reason ~= "unload" then
                Notify("Magic Carpet", tostring(reason), "error")
            end
        end

        Track(UserInputService.InputBegan:Connect(function(input, processed)
            if processed or Listening or Clock() - ConsumedAt < 0.25 then return end
            if input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode == (KeyCodeFrom(Carpet.Key) or KeyCodeFrom("F")) then
                CarpetSet(not Carpet.Enabled)
            end
        end))

        local HelpBody = Groupbox(MRight, { Name = "Controls", Icon = "info", Order = 1 })
        StatRow(HelpBody, "Move", IsTouchOnly() and "Thumbstick" or "W A S D", 1)
        StatRow(HelpBody, "Up / down", "Space / LCtrl", 2)
        StatRow(HelpBody, "Steer", "Camera", 3)
        StatRow(HelpBody, "Mobile", "Thumbstick + camera", 4)
        local note = Label(HelpBody, "Client-side only: the carpet is a local visual on your own character.", 11, "Muted", nil, {
            Size = UDim2.new(1, 0, 0, 34), TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 5, ZIndex = 4,
        })
        New("UIPadding", { Parent = note, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4) })
    end

    ------------------------------------------------------------------ tabs
    local TabDefs = {
        { Id = "Home", Label = "Home", Icon = "layout-grid", Title = "Home", Desc = "Your dashboard at a glance", Page = HomePage, Search = false },
        { Id = "Games", Label = "Games", Icon = "gamepad-2", Title = "Games", Desc = "Pick a game and run its script", Page = GamesPage, Search = true, Badge = tostring(#Games) },
        { Id = "Misc", Label = "Misc", Icon = "play", Title = "Misc", Desc = "Fun extras for your character", Page = MiscPage, Search = false },
        { Id = "Settings", Label = "Settings", Icon = "settings", Title = "Settings", Desc = "Customize your hub", Page = SettingsPage, Search = false },
    }
    local Tabs = {}
    local CurrentTab

    SelectTab = function(id)
        for tid, t in pairs(Tabs) do
            local on = tid == id
            t.def.Page.Visible = on
            Bind(t.label, "TextColor3", on and "Text" or "Muted", 0.15)
            t.label.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
            Bind(t.icon, "ImageColor3", on and "Accent" or "Muted", 0.15)
            if t.badge then
                Bind(t.badge, "BackgroundColor3", on and "Accent" or "Background", 0.15)
                Bind(t.badgeText, "TextColor3", on and "AccentDark" or "Muted", 0.15)
            end
            if on then
                PageTitle.Text = t.def.Title
                PageDesc.Text = t.def.Desc
                SearchWrap.Visible = t.def.Search
                Tween(Indicator, { Position = UDim2.fromOffset(10, (t.index - 1) * 40) }, 0.35, Enum.EasingStyle.Quint)
                if CurrentTab ~= id then
                    -- small slide-in for the page content
                    local pad = t.def.Page:FindFirstChildOfClass("UIPadding")
                    if pad then
                        pad.PaddingTop = UDim.new(0, 30)
                        Tween(pad, { PaddingTop = UDim.new(0, 18) }, 0.3)
                    end
                end
            end
        end
        CurrentTab = id
    end

    for i, def in ipairs(TabDefs) do
        local btn = New("TextButton", {
            Parent = TabStack,
            Size = UDim2.new(1, 0, 0, 38),
            Text = "",
            BackgroundTransparency = 1,
            LayoutOrder = i,
            ZIndex = 5,
        })
        local icon = Icon(btn, def.Icon, 16, "Muted", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            ZIndex = 6,
        })
        local label = Label(btn, def.Label, 13, "Muted", Enum.Font.GothamMedium, {
            Position = UDim2.fromOffset(40, 0),
            Size = UDim2.new(1, -80, 1, 0),
            ZIndex = 6,
        })
        local badge, badgeText
        if def.Badge then
            local b = New("Frame", {
                Parent = btn,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(22, 18),
                ZIndex = 6,
            }, { BackgroundColor3 = "Background" })
            Round(b, "full")
            Outline(b, "Stroke")
            badge = b
            badgeText = Label(b, def.Badge, 10, "Muted", Enum.Font.GothamBold, {
                Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None, ZIndex = 7,
            })
        end
        btn.MouseEnter:Connect(function()
            if CurrentTab ~= def.Id then Bind(label, "TextColor3", "Text", 0.12) end
        end)
        btn.MouseLeave:Connect(function()
            if CurrentTab ~= def.Id then Bind(label, "TextColor3", "Muted", 0.2) end
        end)
        btn.MouseButton1Click:Connect(function() SelectTab(def.Id) end)
        Tabs[def.Id] = { def = def, index = i, label = label, icon = icon, badge = badge, badgeText = badgeText }
    end
    Indicator.Position = UDim2.fromOffset(10, 0)
    SelectTab("Home")

    ------------------------------------------------------------------ minimize pill (mobile friendly)
    local Open = true
    local Pill = New("TextButton", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        Visible = false,
        ZIndex = 30,
    }, { BackgroundColor3 = "Background" })
    Round(Pill, "full")
    Rim(Pill, "StrokeHover", 0.1, 0.7)
    Pressable(Pill, 0.94)
    New("UIPadding", { Parent = Pill, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) })
    New("UIListLayout", {
        Parent = Pill,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 9),
    })
    local PillLogo = New("Frame", { Parent = Pill, Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, ZIndex = 31 }, { BackgroundColor3 = "Accent" })
    Round(PillLogo, "full")
    Shade(PillLogo, 0.68, 60)
    Rim(PillLogo, "Text", 0.4, 1)
    Label(PillLogo, "S", 13, "AccentDark", Enum.Font.GothamBlack, {
        Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None, ZIndex = 32,
    })
    Label(Pill, Config.HubName, 13, "Text", Enum.Font.GothamBold, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 31,
    })
    Label(Pill, "Tap to open", 11, "Muted", nil, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, LayoutOrder = 3, ZIndex = 31,
    })

    local function Show()
        if Open or not Alive then return end
        Open = true
        Pill.Visible = false
        Root.Visible = true
        scale.Scale = target * 0.94
        Cover.Visible = true
        Cover.BackgroundTransparency = 0
        Tween(scale, { Scale = target }, 0.35, Enum.EasingStyle.Back)
        Tween(Cover, { BackgroundTransparency = 1 }, 0.25)
        Tween(ShadowImg, { ImageTransparency = 0.45 }, 0.25)
        task.delay(0.26, function() if Open then Cover.Visible = false end end)
    end

    local function Hide(showPill)
        if not Open then return end
        Open = false
        Cover.Visible = true
        Tween(scale, { Scale = target * 0.94 }, 0.2)
        Tween(Cover, { BackgroundTransparency = 0 }, 0.18)
        Tween(ShadowImg, { ImageTransparency = 1 }, 0.2)
        task.delay(0.21, function()
            if not Open then Root.Visible = false end
        end)
        if showPill or IsTouchOnly() then
            Pill.Visible = true
            local ps = Pill:FindFirstChildOfClass("UIScale")
            if ps then
                ps.Scale = 0.6
                Tween(ps, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
            end
        end
    end

    local pillDragged = MakeDraggable(Pill, Pill)
    Pill.MouseButton1Click:Connect(function()
        if pillDragged() then return end
        Show()
    end)

    IconButton(Header, "x", UDim2.new(1, -18, 0, 22), function()
        Open = false
        Cover.Visible = true
        Tween(scale, { Scale = target * 0.92 }, 0.2)
        Tween(Cover, { BackgroundTransparency = 0 }, 0.2)
        Tween(ShadowImg, { ImageTransparency = 1 }, 0.2)
        task.wait(0.22)
        env.SOLHub_Unload()
    end, "Error")
    IconButton(Header, "minus", UDim2.new(1, -56, 0, 22), function()
        Hide(true)
    end)

    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed or Listening or Clock() - ConsumedAt < 0.25 then return end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == (KeyCodeFrom(State.ToggleKey) or Enum.KeyCode.RightShift) then
            if Open then Hide(false) else Show() end
        end
    end))

    OnViewportChanged(function()
        target = FitScale(W, H)
        if Open then Tween(scale, { Scale = target }, 0.2) end
    end)

    MakeDraggable(Root, SideHeader)
    MakeDraggable(Root, Header)
end

----------------------------------------------------------------------------------------------------
-- Key system
----------------------------------------------------------------------------------------------------

local function OpenKeySystem()
    local W, H = 400, 424
    local INPUT_Y = 198
    local gui = Track(MountGui("SOLHub_Key", 900))

    local Root = New("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = 1,
    })
    Shadow(Root, 0.4)
    local Card = New("Frame", {
        Parent = Root,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    }, { BackgroundColor3 = "Background" })
    Round(Card, 18)
    Rim(Card, "StrokeHover", 0.05, 0.7)
    local Deco = New("Frame", {
        Parent = Card, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2,
    })
    local Glow = New("Frame", {
        Parent = Deco, Size = UDim2.new(1, 0, 0, 190), ZIndex = 2,
    }, { BackgroundColor3 = "Accent" })
    Round(Glow, 18)
    Fade(Glow, 0.84, 1, 90)
    -- concentric rings radiating from the logo
    for _, r in ipairs({ { 96, 0.8 }, { 150, 0.87 }, { 210, 0.93 } }) do
        local ring = New("Frame", {
            Parent = Deco,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0, 64),
            Size = UDim2.fromOffset(r[1], r[1]),
            BackgroundTransparency = 1,
            ZIndex = 2,
        })
        Round(ring, "full")
        local rs = Outline(ring, "Accent", 1, r[2])
        New("UIGradient", { Parent = rs, Rotation = 90, Transparency = Stops({ { 0, 0 }, { 0.55, 0.2 }, { 1, 1 } }) })
    end
    local scale, target = PopIn(Root, W, H)

    IconButton(Card, "x", UDim2.new(1, -14, 0, 14), function()
        Tween(scale, { Scale = target * 0.9 }, 0.18)
        task.wait(0.18)
        env.SOLHub_Unload()
    end, "Error")

    Logo(Card, UDim2.new(0.5, -28, 0, 36), 56, 16, 28, 3, 2.6)

    Label(Card, Config.HubName, 26, "Text", Enum.Font.GothamBlack, {
        Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 30),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
    })
    Label(Card, "Enter your key to unlock the hub", 13, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(0, 142), Size = UDim2.new(1, 0, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
    })

    Label(Card, "LICENSE KEY", 10, "Muted", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(32, INPUT_Y - 19), Size = UDim2.new(1, -64, 0, 12), ZIndex = 3,
    })
    local FocusGlow = SoftGlow(Card, "Accent", UDim2.new(0.5, 0, 0, INPUT_Y + 23), UDim2.new(1, -20, 0, 86), 1, 2)
    local InputWrap = New("Frame", {
        Parent = Card,
        Position = UDim2.fromOffset(30, INPUT_Y),
        Size = UDim2.new(1, -60, 0, 46),
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(InputWrap, 12)
    local InputStroke = Rim(InputWrap, "StrokeHover", 0.2, 0.75)
    local KeyTile = New("Frame", {
        Parent = InputWrap,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        ZIndex = 4,
    }, { BackgroundColor3 = "Surface3" })
    Round(KeyTile, 9)
    local KeyIcon = Icon(KeyTile, "key", 15, "Muted", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
    })
    local KeyBox = New("TextBox", {
        Parent = InputWrap,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(48, 0),
        Size = UDim2.new(1, -60, 1, 0),
        Text = "",
        PlaceholderText = "SOL-KEY-XXXX",
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
    }, { TextColor3 = "Text", PlaceholderColor3 = "Muted" })

    local Status = Label(Card, "", 12, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(0, 362), Size = UDim2.new(1, 0, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
    })
    local function SetStatus(text, key)
        Status.Text = text
        Bind(Status, "TextColor3", key or "Muted", 0.15)
    end

    local FootLine = New("Frame", {
        Parent = Card, Position = UDim2.new(0, 30, 1, -38), Size = UDim2.new(1, -60, 0, 1), ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = FootLine, Transparency = Stops({ { 0, 1 }, { 0.25, 0 }, { 0.75, 0 }, { 1, 1 } }) })
    local Foot = New("Frame", {
        Parent = Card,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -11),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    New("UIListLayout", {
        Parent = Foot, FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    })
    local FootDot = New("Frame", { Parent = Foot, Size = UDim2.fromOffset(6, 6), LayoutOrder = 1, ZIndex = 4 }, { BackgroundColor3 = "Success" })
    Round(FootDot, "full")
    Outline(FootDot, "Success", 3, 0.82)
    Label(Foot, "Executor: " .. ExecutorName() .. "  -  " .. Config.Version, 11, "Muted", Enum.Font.GothamMedium, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 4,
    })

    local attempts, lockedUntil, busy = 0, 0, false
    local SubmitLabel

    local function Shake()
        for _, dx in ipairs({ -8, 8, -6, 6, -3, 0 }) do
            Tween(InputWrap, { Position = UDim2.fromOffset(30 + dx, INPUT_Y) }, 0.04)
            task.wait(0.04)
        end
    end

    local function Submit()
        if busy then return end

        local remaining = lockedUntil - Clock()
        if remaining > 0 then
            SetStatus("Too many attempts, wait " .. math.ceil(remaining) .. "s", "Error")
            return
        end

        local key = Normalize(KeyBox.Text)
        if key == "" then
            SetStatus("Enter a key first", "Error")
            Bind(InputStroke, "Color", "Error", 0.15)
            return
        end

        busy = true
        SubmitLabel.Text = "Verifying..."
        SetStatus("", "Muted")

        local ok = CheckKey(key)
        busy = false
        SubmitLabel.Text = "Verify key"

        if ok then
            SetStatus("Key valid - welcome!", "Success")
            Bind(InputStroke, "Color", "Success", 0.15)
            Bind(KeyIcon, "ImageColor3", "Success", 0.15)
            if State.RememberKey then SaveKey(key) end
            Notify("Access granted", "Welcome to " .. Config.HubName, "success")
            task.wait(0.45)
            Tween(scale, { Scale = target * 0.9 }, 0.2)
            task.wait(0.2)
            pcall(function() gui:Destroy() end)
            ShowLoader(OpenHub)
        else
            attempts = attempts + 1
            KeyBox.Text = ""
            Bind(InputStroke, "Color", "Error", 0.15)
            if attempts >= Config.MaxAttempts then
                attempts = 0
                lockedUntil = Clock() + Config.LockSeconds
                SetStatus("Too many attempts, wait " .. Config.LockSeconds .. "s", "Error")
            else
                SetStatus("Invalid key (" .. attempts .. "/" .. Config.MaxAttempts .. ")", "Error")
            end
            Shake()
        end
    end

    SoftGlow(Card, "Accent", UDim2.new(0.5, 0, 0, INPUT_Y + 86), UDim2.new(1, -40, 0, 84), 0.72, 2)
    local _
    _, SubmitLabel = Chip({
        Parent = Card,
        Position = UDim2.fromOffset(30, INPUT_Y + 58),
        Size = UDim2.new(1, -60, 0, 46),
        Radius = 12,
        Text = "Verify key", Icon = "shield-check", Style = "primary", TextSize = 14, IconSize = 15, ZIndex = 3,
        Callback = Submit,
    })
    Chip({
        Parent = Card,
        Position = UDim2.fromOffset(30, INPUT_Y + 114),
        Size = UDim2.new(1, -60, 0, 40),
        Radius = 12,
        Text = "Get a key", Icon = "external-link", TextSize = 13, ZIndex = 3,
        Callback = function()
            if SetClipboard(Config.SiteURL) then
                Notify("Link copied", "Open the website and click Get Key", "success")
            else
                Notify("Copy failed", "Your executor does not support the clipboard", "error")
            end
        end,
    })

    KeyBox.Focused:Connect(function()
        Bind(InputStroke, "Color", "Accent", 0.15)
        Bind(KeyIcon, "ImageColor3", "Accent", 0.15)
        GlowFade(FocusGlow, 0.78, 0.2)
    end)
    KeyBox.FocusLost:Connect(function(enter)
        Bind(InputStroke, "Color", "StrokeHover", 0.2)
        Bind(KeyIcon, "ImageColor3", "Muted", 0.2)
        GlowFade(FocusGlow, 1, 0.25)
        if enter then task.spawn(Submit) end
    end)

    OnViewportChanged(function()
        target = FitScale(W, H)
        if gui.Parent then scale.Scale = target end
    end)

    MakeDraggable(Root, Card)
end

----------------------------------------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------------------------------------

LoadSettings()
BuildTheme()

local saved = State.RememberKey and LoadKey() or nil
if saved and CheckKey(saved) then
    ShowLoader(function()
        OpenHub()
        Notify("Welcome back", "Key loaded automatically", "success")
    end)
else
    OpenKeySystem()
end
