module Eagle
  # Built-in 3D shader sources (GLSL 330 core / 300 es common subset).
  module Shaders3D
    MAX_LIGHTS = 8

    STANDARD_VERTEX = <<-GLSL
      in vec3 a_position;
      in vec3 a_normal;
      in vec2 a_uv;
      in vec4 a_color;
      uniform mat4 u_model;
      uniform mat4 u_view;
      uniform mat4 u_projection;
      uniform mat3 u_normal_matrix;
      uniform mat4 u_light_matrix;
      uniform vec2 u_uv_scale;
      uniform vec2 u_uv_offset;
      out vec3 v_world_pos;
      out vec3 v_normal;
      out vec2 v_uv;
      out vec4 v_color;
      out vec4 v_light_pos;
      void main() {
        vec4 wp = u_model * vec4(a_position, 1.0);
        v_world_pos = wp.xyz;
        v_normal = normalize(u_normal_matrix * a_normal);
        v_uv = a_uv * u_uv_scale + u_uv_offset;
        v_color = a_color;
        v_light_pos = u_light_matrix * wp;
        gl_Position = u_projection * u_view * wp;
      }
      GLSL

    STANDARD_FRAGMENT = <<-GLSL
      precision highp float;
      #define MAX_LIGHTS #{MAX_LIGHTS}
      in vec3 v_world_pos;
      in vec3 v_normal;
      in vec2 v_uv;
      in vec4 v_color;
      in vec4 v_light_pos;
      out vec4 frag_color;

      uniform vec4 u_albedo;
      uniform sampler2D u_texture;
      uniform int u_has_texture;
      uniform vec3 u_emissive;
      uniform float u_specular;
      uniform float u_shininess;
      uniform float u_metallic;
      uniform int u_unlit;
      uniform float u_alpha_cutoff;

      uniform vec3 u_camera_pos;
      uniform vec3 u_ambient;
      uniform int u_light_count;
      uniform int u_light_type[MAX_LIGHTS];
      uniform vec3 u_light_pos[MAX_LIGHTS];
      uniform vec3 u_light_dir[MAX_LIGHTS];
      uniform vec3 u_light_color[MAX_LIGHTS];
      uniform float u_light_range[MAX_LIGHTS];
      uniform vec2 u_light_spot[MAX_LIGHTS];

      uniform vec3 u_fog_color;
      uniform vec2 u_fog_range;   // start, end (end <= start disables)
      uniform int u_shadows;
      uniform sampler2D u_shadow_map;
      uniform float u_shadow_bias;
      uniform float u_shadow_texel;

      float shadow_factor(vec3 n, vec3 l) {
        if (u_shadows == 0) return 1.0;
        vec3 proj = v_light_pos.xyz / v_light_pos.w;
        proj = proj * 0.5 + 0.5;
        if (proj.z > 1.0 || proj.x < 0.0 || proj.x > 1.0 || proj.y < 0.0 || proj.y > 1.0) return 1.0;
        float bias = max(u_shadow_bias * (1.0 - dot(n, l)), u_shadow_bias * 0.2);
        float lit = 0.0;
        for (int x = -1; x <= 1; x++) {
          for (int y = -1; y <= 1; y++) {
            float d = texture(u_shadow_map, proj.xy + vec2(float(x), float(y)) * u_shadow_texel).r;
            lit += proj.z - bias > d ? 0.0 : 1.0;
          }
        }
        return lit / 9.0;
      }

      void main() {
        vec4 base = u_albedo * v_color;
        if (u_has_texture == 1) base *= texture(u_texture, v_uv);
        if (base.a < u_alpha_cutoff) discard;
        if (u_unlit == 1) {
          vec3 c = base.rgb + u_emissive;
          frag_color = vec4(c, base.a);
        } else {
          vec3 n = normalize(v_normal);
          if (!gl_FrontFacing) n = -n;
          vec3 v = normalize(u_camera_pos - v_world_pos);
          vec3 diffuse_col = mix(base.rgb, vec3(0.0), u_metallic);
          vec3 spec_col = mix(vec3(u_specular), base.rgb, u_metallic);
          vec3 color = u_ambient * base.rgb;
          for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= u_light_count) break;
            vec3 l; float atten = 1.0;
            if (u_light_type[i] == 0) {
              l = normalize(-u_light_dir[i]);
            } else {
              vec3 d = u_light_pos[i] - v_world_pos;
              float dist = length(d);
              l = d / max(dist, 0.0001);
              float r = max(u_light_range[i], 0.0001);
              float f = clamp(1.0 - (dist * dist) / (r * r), 0.0, 1.0);
              atten = f * f;
              if (u_light_type[i] == 2) {
                float cd = dot(-l, normalize(u_light_dir[i]));
                atten *= clamp((cd - u_light_spot[i].y) / max(u_light_spot[i].x - u_light_spot[i].y, 0.0001), 0.0, 1.0);
              }
            }
            float ndl = max(dot(n, l), 0.0);
            if (ndl <= 0.0 || atten <= 0.0) continue;
            float sh = (i == 0) ? shadow_factor(n, l) : 1.0;
            vec3 h = normalize(l + v);
            float spec = pow(max(dot(n, h), 0.0), u_shininess);
            color += (diffuse_col * ndl + spec_col * spec) * u_light_color[i] * atten * sh;
          }
          color += u_emissive;
          if (u_fog_range.y > u_fog_range.x) {
            float dist = length(u_camera_pos - v_world_pos);
            float f = clamp((dist - u_fog_range.x) / (u_fog_range.y - u_fog_range.x), 0.0, 1.0);
            color = mix(color, u_fog_color, f);
          }
          frag_color = vec4(color, base.a);
        }
      }
      GLSL

    DEPTH_VERTEX = <<-GLSL
      in vec3 a_position;
      in vec3 a_normal;
      in vec2 a_uv;
      in vec4 a_color;
      uniform mat4 u_model;
      uniform mat4 u_light_matrix;
      void main() { gl_Position = u_light_matrix * u_model * vec4(a_position, 1.0); }
      GLSL

    DEPTH_FRAGMENT = <<-GLSL
      precision highp float;
      out vec4 frag_color;
      void main() { frag_color = vec4(1.0); }
      GLSL

    SKY_VERTEX = <<-GLSL
      in vec2 a_position;
      in vec2 a_uv;
      in vec4 a_color;
      uniform mat4 u_inv_view_proj;
      out vec3 v_dir;
      void main() {
        vec4 near = u_inv_view_proj * vec4(a_position, -1.0, 1.0);
        vec4 far = u_inv_view_proj * vec4(a_position, 1.0, 1.0);
        v_dir = far.xyz / far.w - near.xyz / near.w;
        gl_Position = vec4(a_position, 0.999999, 1.0);
      }
      GLSL

    SKY_FRAGMENT = <<-GLSL
      precision highp float;
      in vec3 v_dir;
      out vec4 frag_color;
      uniform vec3 u_sky_top;
      uniform vec3 u_sky_horizon;
      uniform vec3 u_sky_bottom;
      uniform vec3 u_sun_dir;
      uniform vec3 u_sun_color;
      void main() {
        vec3 d = normalize(v_dir);
        float t = d.y;
        vec3 c = t > 0.0 ? mix(u_sky_horizon, u_sky_top, pow(t, 0.6)) : mix(u_sky_horizon, u_sky_bottom, pow(-t, 0.5));
        float sun = pow(max(dot(d, -u_sun_dir), 0.0), 256.0);
        float glow = pow(max(dot(d, -u_sun_dir), 0.0), 8.0) * 0.25;
        c += u_sun_color * (sun + glow);
        frag_color = vec4(c, 1.0);
      }
      GLSL
  end

  # Surface appearance for 3D meshes.
  #
  #   mat = Material.new(albedo: Color::RED, shininess: 64)
  #   mat.texture = Texture.load("res://crate.png")
  class Material
    property albedo : Color
    property texture : Texture? = nil
    property emissive : Color = Color::BLACK
    property specular : Float32 = 0.3_f32
    property shininess : Float32 = 32_f32
    property metallic : Float32 = 0_f32
    property? unlit = false
    property? double_sided = false
    property? transparent = false
    property? wireframe = false
    property? cast_shadows = true
    property? receive_shadows = true
    property alpha_cutoff : Float32 = 0.01_f32
    property uv_scale : Vec2 = Vec2::ONE
    property uv_offset : Vec2 = Vec2::ZERO
    property blend : GPU::BlendMode = GPU::BlendMode::Alpha
    # Custom shader (must accept the standard uniforms it uses). nil = standard.
    property shader : Shader? = nil
    # Extra uniforms for custom shaders.
    getter uniforms = {} of String => GPU::UniformValue
    # Render order tweak (higher = later within its pass).
    property priority : Int32 = 0

    @@standard : Shader? = nil

    def initialize(@albedo : Color = Color::WHITE, texture : Texture? = nil, shininess : Number = 32, specular : Number = 0.3, unlit : Bool = false, emissive : Color = Color::BLACK, metallic : Number = 0, transparent : Bool = false)
      @texture = texture
      @shininess = shininess.to_f32; @specular = specular.to_f32
      @unlit = unlit; @emissive = emissive; @metallic = metallic.to_f32; @transparent = transparent
    end

    def self.standard_shader : Shader
      @@standard ||= Shader.new(Shaders3D::STANDARD_VERTEX, Shaders3D::STANDARD_FRAGMENT, Shader::ATTRIBS_3D)
    end

    # :nodoc:
    def self.reset_shared; @@standard = nil; end

    def self.unlit(color : Color = Color::WHITE, texture : Texture? = nil) : Material
      new(color, texture, unlit: true)
    end

    def []=(name : String, v : GPU::UniformValue); @uniforms[name] = v; end

    def effective_shader : Shader; @shader || Material.standard_shader; end

    # Upload material uniforms (the shader must be in use).
    def apply(sh : Shader) : Nil
      sh["u_albedo"] = @albedo
      if t = @texture
        sh.set_texture("u_texture", t, 0)
        sh["u_has_texture"] = 1
      else
        sh.set_texture("u_texture", Texture.white, 0)
        sh["u_has_texture"] = 0
      end
      sh["u_emissive"] = Vec3.new(@emissive.r, @emissive.g, @emissive.b)
      sh["u_specular"] = @specular
      sh["u_shininess"] = @shininess
      sh["u_metallic"] = @metallic
      sh["u_unlit"] = @unlit ? 1 : 0
      sh["u_alpha_cutoff"] = @alpha_cutoff
      sh["u_uv_scale"] = @uv_scale
      sh["u_uv_offset"] = @uv_offset
      @uniforms.each { |k, v| sh[k] = v }
    end
  end
end
