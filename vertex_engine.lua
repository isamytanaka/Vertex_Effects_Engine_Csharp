-- Vertex Effects Engine C# - Lua Compiler
-- Main module

local VertexEngine = {}
local Parser = {}
local Generator = {}
local FileSystem = {}

-- File System utility functions
function FileSystem.createFile(path, content)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

function FileSystem.executeCommand(command)
    local result = os.execute(command)
    return result
end

function FileSystem.checkDeviceLimits()
    local limits = {
        memory = 0,
        processor = "",
        platform = ""
    }
    
    -- Try to detect platform
    if package.config:sub(1,1) == "\\" then
        limits.platform = "Windows"
    else
        limits.platform = "Unix"
    end
    
    -- Try to get memory info using platform-specific commands
    local handle
    if limits.platform == "Windows" then
        handle = io.popen("wmic OS get FreePhysicalMemory")
        if handle then
            local result = handle:read("*a")
            handle:close()
            local memory = result:match("%d+")
            if memory then
                limits.memory = tonumber(memory) * 1024 -- convert KB to bytes
            end
        end
    else
        handle = io.popen("free -b | grep Mem")
        if handle then
            local result = handle:read("*a")
            handle:close()
            local memory = result:match("%d+")
            if memory then
                limits.memory = tonumber(memory)
            end
        end
    end
    
    return limits
end

-- Parser functions
function Parser.tokenize(code)
    local tokens = {}
    local current = ""
    local inString = false
    local stringDelimiter = ""
    
    for i = 1, #code do
        local char = code:sub(i, i)
        
        if inString then
            if char == stringDelimiter then
                inString = false
                current = current .. char
                table.insert(tokens, {type = "string", value = current})
                current = ""
            else
                current = current .. char
            end
        elseif char == '"' or char == "'" then
            if current ~= "" then
                table.insert(tokens, {type = "word", value = current})
                current = ""
            end
            inString = true
            stringDelimiter = char
            current = char
        elseif char:match("%s") then
            if current ~= "" then
                table.insert(tokens, {type = "word", value = current})
                current = ""
            end
        elseif char == "=" or char == "+" or char == "-" or char == "*" or char == "/" then
            if current ~= "" then
                table.insert(tokens, {type = "word", value = current})
                current = ""
            end
            table.insert(tokens, {type = "operator", value = char})
        else
            current = current .. char
        end
    end
    
    if current ~= "" then
        table.insert(tokens, {type = "word", value = current})
    end
    
    return tokens
end

function Parser.parse(tokens)
    local ast = {
        type = "program",
        effects = {}
    }
    
    local i = 1
    local currentEffect = nil
    local currentBlock = nil
    
    while i <= #tokens do
        local token = tokens[i]
        
        if token.type == "word" then
            if token.value == "effect" and tokens[i+1] then
                currentEffect = {
                    type = "effect",
                    name = tokens[i+1].value,
                    requires = {},
                    params = {},
                    animations = {},
                    events = {},
                    renders = {}
                }
                table.insert(ast.effects, currentEffect)
                i = i + 2
            elseif token.value == "requires" and tokens[i+1] and currentEffect then
                table.insert(currentEffect.requires, tokens[i+1].value)
                i = i + 2
            elseif token.value == "param" and tokens[i+1] and tokens[i+2] and tokens[i+3] and tokens[i+4] and currentEffect then
                table.insert(currentEffect.params, {
                    type = tokens[i+1].value,
                    name = tokens[i+2].value,
                    value = tokens[i+4].value
                })
                i = i + 5
            elseif token.value == "animate" and tokens[i+1] and tokens[i+2] and tokens[i+3] and tokens[i+4] and tokens[i+5] and tokens[i+6] and currentEffect then
                table.insert(currentEffect.animations, {
                    property = tokens[i+1].value,
                    from = tokens[i+3].value,
                    to = tokens[i+5].value,
                    duration = tokens[i+7].value
                })
                i = i + 8
            elseif token.value == "on" and tokens[i+1] and tokens[i+2] and currentEffect then
                currentBlock = {
                    type = "event",
                    event = tokens[i+1].value,
                    actions = {}
                }
                table.insert(currentEffect.events, currentBlock)
                i = i + 3
            elseif token.value == "render" and tokens[i+1] and tokens[i+2] and tokens[i+3] and currentEffect then
                table.insert(currentEffect.renders, {
                    object = tokens[i+1].value,
                    properties = tokens[i+3].value
                })
                i = i + 4
            elseif token.value == "end" and tokens[i+1] then
                if tokens[i+1].value == "effect" then
                    currentEffect = nil
                else
                    currentBlock = nil
                end
                i = i + 2
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    
    return ast
end

-- Generator functions
function Generator.generateCode(ast)
    local code = Generator.generateHeader()
    
    for _, effect in ipairs(ast.effects) do
        code = code .. Generator.generateEffect(effect)
    end
    
    code = code .. Generator.generateFooter()
    return code
end

function Generator.generateHeader()
    return [[
using System;
using System.Collections.Generic;
using UnityEngine;

namespace VertexEffects
{
    public class VertexEffectsEngine
    {
        private static VertexEffectsEngine _instance;
        public static VertexEffectsEngine Instance
        {
            get
            {
                if (_instance == null)
                {
                    _instance = new VertexEffectsEngine();
                }
                return _instance;
            }
        }
        
        private Dictionary<string, EffectBase> _effects = new Dictionary<string, EffectBase>();
        
        public void Initialize()
        {
]]
end

function Generator.generateFooter()
    return [[
        }
        
        public EffectBase GetEffect(string name)
        {
            if (_effects.ContainsKey(name))
            {
                return _effects[name];
            }
            return null;
        }
    }
    
    public abstract class EffectBase
    {
        public string Name { get; protected set; }
        public abstract void Apply(GameObject target);
        public abstract void Update(float deltaTime);
    }
}
]]
end

function Generator.generateEffect(effect)
    local code = string.format([[
            // Register %s effect
            _effects.Add("%s", new %sEffect());
]], effect.name, effect.name, effect.name)
    
    code = code .. string.format([[
    
    public class %sEffect : EffectBase
    {
        public %sEffect()
        {
            Name = "%s";
        }
]], effect.name, effect.name, effect.name)
    
    -- Generate parameters
    for _, param in ipairs(effect.params) do
        code = code .. string.format([[
        public %s %s { get; set; } = %s;
]], param.type, param.name, param.value)
    end
    
    -- Generate Apply method
    code = code .. [[
        
        public override void Apply(GameObject target)
        {
]]
    
    for _, render in ipairs(effect.renders) do
        code = code .. string.format([[
            // Render %s
            var renderer = target.GetComponent<Renderer>();
            if (renderer != null)
            {
                renderer.material.SetFloat("%s", %s);
            }
]], render.object, render.object, render.properties)
    end
    
    code = code .. [[
        }
]]
    
    -- Generate Update method
    code = code .. [[
        
        public override void Update(float deltaTime)
        {
]]
    
    for _, animation in ipairs(effect.animations) do
        code = code .. string.format([[
            // Animate %s
            %s = Mathf.Lerp(%s, %s, deltaTime / %s);
]], animation.property, animation.property, animation.from, animation.to, animation.duration)
    end
    
    code = code .. [[
        }
    }
]]
    
    return code
end

-- Main function to compile DSL to C#
function VertexEngine.compile(sourceCode, outputPath)
    local tokens = Parser.tokenize(sourceCode)
    local ast = Parser.parse(tokens)
    local csharpCode = Generator.generateCode(ast)
    
    if outputPath then
        return FileSystem.createFile(outputPath, csharpCode)
    else
        return csharpCode
    end
end

-- Execute a DSL script
function VertexEngine.execute(filename)
    local file = io.open(filename, "r")
    if not file then
        return false, "Could not open file: " .. filename
    end
    
    local content = file:read("*all")
    file:close()
    
    local outputPath = filename:gsub("%.vfx$", ".cs")
    local success = VertexEngine.compile(content, outputPath)
    
    if success then
        return true, "Compiled to: " .. outputPath
    else
        return false, "Failed to compile: " .. filename
    end
end

-- Check system compatibility
function VertexEngine.checkCompatibility()
    local limits = FileSystem.checkDeviceLimits()
    local compatible = true
    local issues = {}
    
    if limits.memory and limits.memory < 1024 * 1024 * 50 then
        compatible = false
        table.insert(issues, "Low memory: at least 50MB required")
    end
    
    return compatible, issues
end

return VertexEngine
