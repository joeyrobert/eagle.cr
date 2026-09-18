require "./vec2"
require "./vec3"
require "./mat4"
require "./quat"
require "./rect"
require "./color"
require "./transform2d"

module Eagle
  # Scalar helpers for game math: angles, interpolation, clamping, snapping and smoothing.
  #
  # Everything takes any `Number` and returns `Float32`, so you can mix `Int32`
  # literals with `Float32` fields without casting. The module is `extend self`,
  # so call functions as `Mathf.lerp(...)`.
  #
  # The most useful ones in day-to-day game code:
  #
  # * `lerp` / `inverse_lerp` / `remap` convert between ranges (health to bar width,
  #   distance to volume).
  # * `damp` smooths a value toward a target at the same speed regardless of frame rate.
  #   Use it instead of `a = lerp(a, b, 0.1)`, which runs faster at higher FPS.
  # * `move_toward` steps toward a target by a fixed amount without overshooting,
  #   which suits acceleration and cooldown timers.
  # * `angle_diff` / `lerp_angle` turn toward an angle the short way round.
  #
  # ```
  # class Turret < Node2D
  #   @target : Vec2 = v2(400, 300)
  #
  #   def process(dt : Float32) : Nil
  #     # Turn toward the target, smoothly and frame-rate independent.
  #     want = (@target - position).angle
  #     self.rotation = Mathf.lerp_angle(rotation, want, 1 - Math.exp(-8 * dt))
  #   end
  # end
  #
  # volume = Mathf.remap(120, 0, 400, 1.0, 0.0) # => 0.7 (quieter as distance grows)
  # speed = Mathf.move_toward(0, 300, 50)        # => 50.0 (accelerate by 50 per call)
  # ```
  module Mathf
    extend self

    # One full turn in radians (2π). Handy for "spin once per second": `rotation += Mathf::TAU * dt`.
    TAU = (Math::PI * 2).to_f32
    # π as a `Float32`, so it mixes with engine fields without casting.
    PI  = Math::PI.to_f32
    # Default tolerance used by `approx?`.
    EPS = 1e-6_f32

    # Converts degrees to radians. Engine angles are always radians.
    def deg2rad(d : Number) : Float32; (d * Math::PI / 180).to_f32; end
    # Converts radians to degrees, for display or for authoring in degrees.
    def rad2deg(r : Number) : Float32; (r * 180 / Math::PI).to_f32; end
    # Linear interpolation: returns *a* when *t* is 0, *b* when *t* is 1, and a proportional
    # mix in between. *t* is not clamped, so values outside 0..1 extrapolate.
    #
    # ```
    # Mathf.lerp(0, 100, 0.25) # => 25.0
    # ```
    def lerp(a : Number, b : Number, t : Number) : Float32; (a + (b - a) * t).to_f32; end
    # The inverse of `lerp`: where *v* sits between *a* and *b*, as a fraction.
    # Returns 0 when *a* equals *b*.
    #
    # ```
    # Mathf.inverse_lerp(10, 20, 15) # => 0.5
    # ```
    def inverse_lerp(a : Number, b : Number, v : Number) : Float32; b == a ? 0_f32 : ((v - a) / (b - a)).to_f32; end
    # Maps *v* from the range *a*..*b* onto the range *c*..*d*.
    #
    # ```
    # bar_width = Mathf.remap(35, 0, 100, 0, 200) # health 35/100 => 70px bar
    # ```
    def remap(v : Number, a : Number, b : Number, c : Number, d : Number) : Float32; lerp(c, d, inverse_lerp(a, b, v)); end
    # Restricts *v* to *lo*..*hi*. Keeps the input's numeric type.
    def clamp(v : Number, lo : Number, hi : Number); v < lo ? lo : (v > hi ? hi : v); end
    # Restricts *v* to 0..1 and returns a `Float32`.
    def clamp01(v : Number) : Float32; clamp(v, 0, 1).to_f32; end
    # Hermite ease between 0 and 1 as *t* moves from *a* to *b*, with zero slope at both ends.
    # Good for fades and soft thresholds.
    def smoothstep(a : Number, b : Number, t : Number) : Float32
      x = clamp01(inverse_lerp(a, b, t))
      x * x * (3 - 2 * x)
    end
    # Returns -1, 0 or 1 depending on the sign of *v*.
    def sign(v : Number) : Int32; v > 0 ? 1 : (v < 0 ? -1 : 0); end
    # True when *a* and *b* differ by at most *eps*. Use it instead of `==` on floats.
    def approx?(a : Number, b : Number, eps = EPS) : Bool; (a - b).abs <= eps; end
    # Wraps *v* into the half-open range *lo*...*hi*, like a modulo that works for floats
    # and negative numbers. Useful for screen wrap-around.
    #
    # ```
    # Mathf.wrap(-10, 0, 800) # => 790.0
    # ```
    def wrap(v : Number, lo : Number, hi : Number)
      range = hi - lo
      return lo if range == 0
      v - range * ((v - lo) / range).floor
    end
    # Normalizes an angle to -π..π.
    def wrap_angle(r : Number) : Float32; wrap(r, -Math::PI, Math::PI).to_f32; end
    # Shortest signed difference from *from* to *to*, in -π..π. Positive means turn
    # clockwise in Eagle's y-down screen space.
    def angle_diff(from : Number, to : Number) : Float32; wrap_angle(to - from); end
    # Interpolates between two angles the short way round, so 350° to 10° goes through 0°
    # instead of spinning backwards.
    def lerp_angle(from : Number, to : Number, t : Number) : Float32; (from + angle_diff(from, to) * t).to_f32; end
    # Moves *from* toward *to* by at most *delta* and never overshoots.
    #
    # ```
    # speed, max_speed, accel = 0.0, 300.0, 900.0
    # speed = Mathf.move_toward(speed, max_speed, accel * dt)
    # ```
    def move_toward(from : Number, to : Number, delta : Number) : Float32
      (to - from).abs <= delta ? to.to_f32 : (from + sign(to - from) * delta).to_f32
    end
    # Frame-rate independent smoothing: moves *a* toward *b*, and higher *lambda* moves faster.
    # Around 5 feels soft, 10 to 20 feels snappy. Call it every frame with that frame's *dt*.
    #
    # ```
    # cam_x, player_x = 0.0, 250.0
    # cam_x = Mathf.damp(cam_x, player_x, 10, dt) # call every frame
    # ```
    def damp(a : Number, b : Number, lambda : Number, dt : Number) : Float32
      lerp(a, b, 1 - Math.exp(-lambda * dt))
    end
    # `damp` for `Vec2`, for smoothing positions such as a camera following a player.
    def damp(a : Vec2, b : Vec2, lambda : Number, dt : Number) : Vec2; a.lerp(b, 1 - Math.exp(-lambda * dt)); end
    # `damp` for `Vec3`.
    def damp(a : Vec3, b : Vec3, lambda : Number, dt : Number) : Vec3; a.lerp(b, 1 - Math.exp(-lambda * dt)); end
    # Rounds *v* to the nearest multiple of *step*, for grid snapping. A step of 0 returns *v* unchanged.
    #
    # ```
    # Mathf.snapped(37, 16) # => 32.0
    # ```
    def snapped(v : Number, step : Number) : Float32; step == 0 ? v.to_f32 : ((v / step).round * step).to_f32; end
    # Bounces *v* back and forth between 0 and *length*, for patrols and pulsing effects.
    #
    # ```
    # x = Mathf.ping_pong(Clock.elapsed * 100, 300) # slides 0..300..0
    # ```
    def ping_pong(v : Number, length : Number) : Float32
      l2 = length * 2
      t = v - l2 * (v / l2).floor
      (length - (t - length).abs).to_f32
    end
  end
end
