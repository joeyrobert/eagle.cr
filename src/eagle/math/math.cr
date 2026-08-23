require "./vec2"
require "./vec3"
require "./mat4"
require "./quat"
require "./rect"
require "./color"
require "./transform2d"

module Eagle
  # Extra scalar helpers, in the style of Godot's @GlobalScope.
  module Mathf
    extend self

    TAU = (Math::PI * 2).to_f32
    PI  = Math::PI.to_f32
    EPS = 1e-6_f32

    def deg2rad(d : Number) : Float32; (d * Math::PI / 180).to_f32; end
    def rad2deg(r : Number) : Float32; (r * 180 / Math::PI).to_f32; end
    def lerp(a : Number, b : Number, t : Number) : Float32; (a + (b - a) * t).to_f32; end
    def inverse_lerp(a : Number, b : Number, v : Number) : Float32; b == a ? 0_f32 : ((v - a) / (b - a)).to_f32; end
    def remap(v : Number, a : Number, b : Number, c : Number, d : Number) : Float32; lerp(c, d, inverse_lerp(a, b, v)); end
    def clamp(v : Number, lo : Number, hi : Number); v < lo ? lo : (v > hi ? hi : v); end
    def clamp01(v : Number) : Float32; clamp(v, 0, 1).to_f32; end
    def smoothstep(a : Number, b : Number, t : Number) : Float32
      x = clamp01(inverse_lerp(a, b, t))
      x * x * (3 - 2 * x)
    end
    def sign(v : Number) : Int32; v > 0 ? 1 : (v < 0 ? -1 : 0); end
    def approx?(a : Number, b : Number, eps = EPS) : Bool; (a - b).abs <= eps; end
    def wrap(v : Number, lo : Number, hi : Number)
      range = hi - lo
      return lo if range == 0
      v - range * ((v - lo) / range).floor
    end
    def wrap_angle(r : Number) : Float32; wrap(r, -Math::PI, Math::PI).to_f32; end
    # Shortest signed difference between two angles.
    def angle_diff(from : Number, to : Number) : Float32; wrap_angle(to - from); end
    def lerp_angle(from : Number, to : Number, t : Number) : Float32; (from + angle_diff(from, to) * t).to_f32; end
    def move_toward(from : Number, to : Number, delta : Number) : Float32
      (to - from).abs <= delta ? to.to_f32 : (from + sign(to - from) * delta).to_f32
    end
    # Framerate-independent exponential decay (Freya Holmér style).
    def damp(a : Number, b : Number, lambda : Number, dt : Number) : Float32
      lerp(a, b, 1 - Math.exp(-lambda * dt))
    end
    def damp(a : Vec2, b : Vec2, lambda : Number, dt : Number) : Vec2; a.lerp(b, 1 - Math.exp(-lambda * dt)); end
    def damp(a : Vec3, b : Vec3, lambda : Number, dt : Number) : Vec3; a.lerp(b, 1 - Math.exp(-lambda * dt)); end
    def snapped(v : Number, step : Number) : Float32; step == 0 ? v.to_f32 : ((v / step).round * step).to_f32; end
    def ping_pong(v : Number, length : Number) : Float32
      l2 = length * 2
      t = v - l2 * (v / l2).floor
      (length - (t - length).abs).to_f32
    end
  end
end
