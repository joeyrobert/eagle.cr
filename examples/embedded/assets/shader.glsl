#effect
vec4 effect(vec4 c, sampler2D t, vec2 uv, vec2 sc) { return texture(t, uv) * vec4(0.5 + 0.5 * sin(u_time * 3.0), 1.0, 1.0, 1.0) * c; }
