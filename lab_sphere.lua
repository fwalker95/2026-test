-- lab_sphere.lua
-- 3D-looking spinning sphere rendered in 2D screen space using normals + lighting.
local LabSphere = {}
LabSphere.__index = LabSphere

local vertexShader = [[
attribute vec3 VertexNormal;
varying vec3 vNormal;

uniform float uAngle;
uniform float uTilt;
uniform vec2  uCenter;
uniform float uRadius;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float cy = cos(uAngle), sy = sin(uAngle);
    mat3 rotY = mat3(cy, 0.0, -sy,
                     0.0, 1.0,  0.0,
                     sy, 0.0,  cy);

    float cx = cos(uTilt), sx = sin(uTilt);
    mat3 rotX = mat3(1.0, 0.0, 0.0,
                     0.0,  cx,  sx,
                     0.0, -sx,  cx);

    mat3 rot = rotX * rotY;
    vec3 p = rot * vertex_position.xyz;
    vNormal = normalize(rot * VertexNormal);

    vec4 screen = vec4(uCenter.x + p.x * uRadius,
                       uCenter.y - p.y * uRadius,
                       0.0, 1.0);
    return transform_projection * screen;
}
]]

local fragmentShader = [[
varying vec3 vNormal;

uniform vec3 uLightDir;
uniform vec3 uBaseColor;
uniform float uShowNormals;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc)
{
    if (vNormal.z < 0.0) discard;

    vec3 n = normalize(vNormal);
    if (uShowNormals > 0.5) {
        return vec4(n * 0.5 + 0.5, 1.0) * color;
    }

    vec3 L = normalize(uLightDir);
    float diff = max(dot(n, L), 0.0);

    vec3 V = vec3(0.0, 0.0, 1.0);
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(n, H), 0.0), 40.0);

    vec3 lit = uBaseColor * (0.18 + 0.82 * diff) + vec3(spec) * 0.55;
    return vec4(lit, 1.0) * color;
}
]]

local function buildSphereMesh(latSteps, lonSteps)
    local format = {
        { "VertexPosition", "float", 3 },
        { "VertexNormal", "float", 3 },
    }

    local vertices = {}
    for i = 0, latSteps do
        local theta = math.pi * i / latSteps
        local st, ct = math.sin(theta), math.cos(theta)
        for j = 0, lonSteps do
            local phi = (2.0 * math.pi) * j / lonSteps
            local x = st * math.cos(phi)
            local y = ct
            local z = st * math.sin(phi)
            vertices[#vertices + 1] = { x, y, z, x, y, z }
        end
    end

    local map = {}
    local stride = lonSteps + 1
    for i = 0, latSteps - 1 do
        for j = 0, lonSteps - 1 do
            local a = i * stride + j + 1
            local b = a + stride
            map[#map + 1] = a
            map[#map + 1] = b
            map[#map + 1] = a + 1
            map[#map + 1] = a + 1
            map[#map + 1] = b
            map[#map + 1] = b + 1
        end
    end

    local mesh = love.graphics.newMesh(format, vertices, "triangles", "static")
    mesh:setVertexMap(map)
    return mesh
end

function LabSphere.new(opts)
    opts = opts or {}
    local self = setmetatable({}, LabSphere)
    self.mesh = buildSphereMesh(opts.latSteps or 24, opts.lonSteps or 36)
    self.shader = love.graphics.newShader(vertexShader, fragmentShader)

    self.angle = 0
    self.spinSpeed = opts.spinSpeed or 1.1
    self.tilt = opts.tilt or 0.35
    self.baseColor = opts.baseColor or { 0.35, 0.75, 1.0 }
    self.showNormals = false

    return self
end

function LabSphere:update(dt)
    self.angle = (self.angle + self.spinSpeed * dt) % (math.pi * 2)
end

function LabSphere:draw(cx, cy, radius)
    local sh = self.shader
    sh:send("uAngle", self.angle)
    sh:send("uTilt", self.tilt)
    sh:send("uCenter", { cx, cy })
    sh:send("uRadius", radius)
    sh:send("uLightDir", { -0.45, 0.6, 0.7 })
    sh:send("uBaseColor", self.baseColor)
    sh:send("uShowNormals", self.showNormals and 1.0 or 0.0)

    love.graphics.setShader(sh)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.mesh)
    love.graphics.setShader()
end

return LabSphere
