-- RobloxMock.lua
-- Busted helper: injects Roblox globals so game modules can be required
-- outside Studio. Loaded automatically via .busted before any spec runs.

-- ---------------------------------------------------------------------------
-- package.path — allow require("src.server.modules.Config") from project root
-- ---------------------------------------------------------------------------
package.path = "./?.lua;" .. package.path

-- ---------------------------------------------------------------------------
-- Primitive math types
-- ---------------------------------------------------------------------------

Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end

function Vector3:__add(o)
    return Vector3.new(self.X + o.X, self.Y + o.Y, self.Z + o.Z)
end

function Vector3:__sub(o)
    return Vector3.new(self.X - o.X, self.Y - o.Y, self.Z - o.Z)
end

function Vector3:__mul(s)
    if type(s) == "number" then
        return Vector3.new(self.X * s, self.Y * s, self.Z * s)
    end
    return Vector3.new(self.X * s.X, self.Y * s.Y, self.Z * s.Z)
end

function Vector3:__tostring()
    return ("Vector3(%g, %g, %g)"):format(self.X, self.Y, self.Z)
end

function Vector3:magnitude()
    return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
end

-- Allow (Vector3 - Vector3).Magnitude and .Unit style access
Vector3.__index = function(t, k)
    if k == "Magnitude" then
        return math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2)
    end
    if k == "Unit" then
        local mag = math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2)
        if mag == 0 then return Vector3.new(0, 0, 0) end
        return Vector3.new(t.X / mag, t.Y / mag, t.Z / mag)
    end
    return Vector3[k]
end

-- ---------------------------------------------------------------------------

BrickColor = {}
BrickColor.__index = BrickColor

function BrickColor.new(name)
    return setmetatable({ Name = name or "Medium stone grey" }, BrickColor)
end

function BrickColor:__tostring()
    return "BrickColor(" .. self.Name .. ")"
end

-- ---------------------------------------------------------------------------

Color3 = {}
Color3.__index = Color3

function Color3.new(r, g, b)
    return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end

function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- ---------------------------------------------------------------------------

CFrame = {}
CFrame.__index = CFrame

local function makeCFrame()
    return setmetatable({}, CFrame)
end

function CFrame.new(...)
    return makeCFrame()
end

function CFrame.Angles(...)
    return makeCFrame()
end

CFrame.__mul = function(a, _b)
    return a
end

-- ---------------------------------------------------------------------------
-- Enum — generate stub namespaces on-demand
-- ---------------------------------------------------------------------------

Enum = setmetatable({}, {
    __index = function(_t, ns)
        return setmetatable({}, {
            __index = function(_t2, key)
                return ns .. "." .. key
            end,
        })
    end,
})

-- ---------------------------------------------------------------------------
-- Instance factory
-- ---------------------------------------------------------------------------

-- Builds a fresh mock Instance table for the given className.
Instance = {}
function Instance.new(className)
    local inst = {
        ClassName        = className,
        Name             = className,
        _parent          = nil,
        _children        = {},
        -- common properties (modules set these directly)
        Anchored         = false,
        CanCollide       = true,
        Transparency     = 0,
        Material         = "SmoothPlastic",
        Size             = Vector3.new(1, 1, 1),
        Position         = Vector3.new(0, 0, 0),
        AssemblyLinearVelocity = Vector3.new(0, 0, 0),
        RequiresHandle   = false,
    }

    -- -----------------------------------------------------------------------
    -- Child management
    -- -----------------------------------------------------------------------
    function inst:FindFirstChild(name)
        for _, c in ipairs(self._children) do
            if c.Name == name then return c end
        end
        return nil
    end

    function inst:FindFirstChildOfClass(cls)
        for _, c in ipairs(self._children) do
            if c.ClassName == cls then return c end
        end
        return nil
    end

    function inst:GetChildren()
        local copy = {}
        for i, c in ipairs(self._children) do copy[i] = c end
        return copy
    end

    function inst:GetDescendants()
        local result = {}
        local function collect(obj)
            for _, c in ipairs(obj._children) do
                table.insert(result, c)
                collect(c)
            end
        end
        collect(self)
        return result
    end

    function inst:IsA(cls)
        return self.ClassName == cls
    end

    function inst:Destroy()
        if self._parent then
            local siblings = self._parent._children
            for i, s in ipairs(siblings) do
                if s == self then
                    table.remove(siblings, i)
                    break
                end
            end
        end
        self._parent = nil
        self._children = {}
    end

    -- -----------------------------------------------------------------------
    -- Parent property — automatically registers child
    -- -----------------------------------------------------------------------
    local mt = {
        __newindex = function(t, k, v)
            if k == "Parent" then
                -- Remove from old parent
                if t._parent and t._parent._children then
                    local old = t._parent._children
                    for i, s in ipairs(old) do
                        if s == t then table.remove(old, i); break end
                    end
                end
                rawset(t, "_parent", v)
                if v and v._children then
                    table.insert(v._children, t)
                end
            else
                rawset(t, k, v)
            end
        end,
        __index = function(t, k)
            if k == "Parent" then return rawget(t, "_parent") end
            return rawget(t, k)
        end,
    }
    setmetatable(inst, mt)

    -- -----------------------------------------------------------------------
    -- Class-specific properties / signals
    -- -----------------------------------------------------------------------
    if className == "RemoteEvent" then
        local handlers = {}
        inst.OnServerEvent = {
            Connect = function(_self, fn)
                table.insert(handlers, fn)
                return { Disconnect = function() end }
            end,
            _fire = function(_self, ...)
                for _, fn in ipairs(handlers) do fn(...) end
            end,
        }
        inst.FireClient = function(_self, _player, ...) end
        inst.FireAllClients = function(_self, ...) end

    elseif className == "IntValue" then
        rawset(inst, "Value", 0)

    elseif className == "BoolValue" then
        rawset(inst, "Value", false)

    elseif className == "StringValue" then
        rawset(inst, "Value", "")

    elseif className == "Humanoid" then
        rawset(inst, "Health", 100)
        rawset(inst, "MaxHealth", 100)
        rawset(inst, "WalkSpeed", 16)
        rawset(inst, "JumpPower", 50)
        inst.TakeDamage = function(self, amount)
            rawset(self, "Health", math.max(0, rawget(self, "Health") - amount))
        end
        inst.MoveTo = function(_self, _) end

    elseif className == "ProximityPrompt" then
        local triggerHandlers = {}
        inst.Triggered = {
            Connect = function(_self, fn)
                table.insert(triggerHandlers, fn)
                return { Disconnect = function() end }
            end,
            _fire = function(_self, player)
                for _, fn in ipairs(triggerHandlers) do fn(player) end
            end,
        }

    elseif className == "BindableEvent" then
        local handlers = {}
        inst.Event = {
            Connect = function(_self, fn)
                table.insert(handlers, fn)
                return { Disconnect = function() end }
            end,
        }
        inst.Fire = function(_self, ...)
            for _, fn in ipairs(handlers) do fn(...) end
        end

    elseif className == "SelectionBox" then
        rawset(inst, "Color3", Color3.new(0, 1, 0))
        rawset(inst, "LineThickness", 0.05)

    elseif className == "Sound" then
        inst.Play = function(_self) end

    elseif className == "PointLight" then
        rawset(inst, "Brightness", 1)
        rawset(inst, "Range", 10)

    elseif className == "Decal" then
        rawset(inst, "Texture", "")

    elseif className == "WeldConstraint" then
        rawset(inst, "Part0", nil)
        rawset(inst, "Part1", nil)

    elseif className == "Tool" then
        rawset(inst, "RequiresHandle", false)
    end

    -- Touched signal — available on all Part-like instances
    if className == "Part" or className == "WedgePart" or className == "BasePart" then
        local touchHandlers = {}
        inst.Touched = {
            Connect = function(_self, fn)
                table.insert(touchHandlers, fn)
                return { Disconnect = function() end }
            end,
            _fire = function(_self, hitPart)
                for _, fn in ipairs(touchHandlers) do fn(hitPart) end
            end,
        }
        inst.IsA = function(self, cls)
            return cls == "BasePart" or cls == self.ClassName
        end
    end

    -- Destroying signal — available on all instances (especially Model)
    local destroyHandlers = {}
    inst.Destroying = {
        Connect = function(_, fn)
            table.insert(destroyHandlers, fn)
            return { Disconnect = function() end }
        end,
        _fire = function(_)
            for _, fn in ipairs(destroyHandlers) do fn() end
        end,
    }

    -- Model: PrimaryPart property
    if className == "Model" then
        rawset(inst, "PrimaryPart", nil)
    end

    return inst
end

-- ---------------------------------------------------------------------------
-- game / services
-- ---------------------------------------------------------------------------

local _services = {}

local function makeService(name)
    local svc = { _name = name, ClassName = name, _children = {} }

    function svc:FindFirstChild(n)
        for _, c in ipairs(self._children) do
            if c.Name == n then return c end
        end
        return nil
    end

    if name == "Players" then
        svc._playerList = {}
        svc._onPlayerAdded = nil
        svc._onPlayerRemoving = nil
        svc._charMap = {}   -- character model -> player mapping

        function svc:GetPlayers() return self._playerList end

        function svc:GetPlayerFromCharacter(character)
            return self._charMap[character]
        end

        -- Helper used in tests: register a character -> player mapping
        function svc:_registerCharacter(player, character)
            self._charMap[character] = player
        end

        svc.PlayerAdded = {
            Connect = function(_self, fn) svc._onPlayerAdded = fn end,
        }
        svc.PlayerRemoving = {
            Connect = function(_self, fn) svc._onPlayerRemoving = fn end,
        }

    elseif name == "DataStoreService" then
        local stores = {}
        function svc:GetDataStore(key)
            if not stores[key] then
                local data = {}
                stores[key] = {
                    GetAsync = function(_self, k) return data[k] end,
                    SetAsync = function(_self, k, v) data[k] = v end,
                    _data = data,
                }
            end
            return stores[key]
        end
        svc._stores = stores

    elseif name == "TweenService" then
        local mockTween = { Play = function() end, Completed = { Wait = function() end } }
        function svc:Create(_inst, _info, _props)
            return mockTween
        end

    elseif name == "Debris" then
        function svc:AddItem(_inst, _lifetime) end

    elseif name == "RunService" then
        svc.Heartbeat = {
            Connect = function(_self, _fn)
                return { Disconnect = function() end }
            end,
        }
    end

    return svc
end

game = setmetatable({}, {
    __index = function(_t, k)
        if k == "GetService" then
            return function(_self, name)
                if not _services[name] then
                    _services[name] = makeService(name)
                end
                return _services[name]
            end
        end
        if k == "BindToClose" then
            return function(_self, _fn) end
        end
        return nil
    end,
})

-- Helper: reset all service singletons between tests
function _G.resetServices()
    _services = {}
end

-- ---------------------------------------------------------------------------
-- workspace
-- ---------------------------------------------------------------------------

workspace = {
    ClassName = "Workspace",
    _children = {},
}

function workspace:FindFirstChild(name)
    for _, c in ipairs(self._children) do
        if c.Name == name then return c end
    end
    return nil
end

function workspace:GetDescendants()
    local result = {}
    local function collect(obj)
        for _, c in ipairs(obj._children) do
            table.insert(result, c)
            if c._children then collect(c) end
        end
    end
    collect(self)
    return result
end

function _G.resetWorkspace()
    workspace._children = {}
end

-- ---------------------------------------------------------------------------
-- task — synchronous no-ops for deterministic tests
-- ---------------------------------------------------------------------------

task = {
    wait  = function(_) end,
    -- spawn is a NO-OP: prevents while-alive AI loops from running synchronously
    spawn = function() end,
    delay = function(_, fn, ...) if fn then fn(...) end end,
}

-- tick() — Roblox global for timestamps; map to os.clock for tests
tick = os.clock

-- ---------------------------------------------------------------------------
-- script — mock for modules that reference script.Parent at load time
-- ---------------------------------------------------------------------------

script = {
    ClassName = "ModuleScript",
    Name      = "MockScript",
    _children = {},
    _parent   = nil,
}

function script:FindFirstChild(name)
    for _, c in ipairs(self._children) do
        if c.Name == name then return c end
    end
    return nil
end

-- Provide a mock Parent for RemoteEvents.lua (needs script.Parent = Shared folder)
local _sharedFolder = {
    ClassName = "Folder",
    Name      = "Shared",
    _children = {},
}

function _sharedFolder:FindFirstChild(name)
    for _, c in ipairs(self._children) do
        if c.Name == name then return c end
    end
    return nil
end

script.Parent = _sharedFolder
_G._mockSharedFolder = _sharedFolder

-- ---------------------------------------------------------------------------
-- Roblox globals not yet covered
-- ---------------------------------------------------------------------------

warn = function(...) end   -- suppress Roblox warnings in tests

-- TweenInfo constructor stub
TweenInfo = {}
function TweenInfo.new(...)
    return {}
end

-- math.huge, math.rad, math.sqrt — already standard Lua
-- os.clock, os.time — already standard Lua
-- ipairs, pairs, type, tostring, table, string — all standard Lua
