module Portal3
  # The first-person character. Movement follows Portal rather than a generic shooter:
  # no jump, a walk speed that feels deliberate, and a crouch that lets the player
  # pass under observation glass. All of the interesting traversal is meant to happen
  # through portals.
  class Player < KinematicBody3D
    # Radius and height of the standing capsule. The body origin sits at its centre,
    # so a body resting on a floor at y=0 sits at y = HEIGHT / 2.
    RADIUS        = 0.32_f32
    HEIGHT        =  1.8_f32
    CROUCH_HEIGHT = 1.15_f32
    EYE_STAND     = 1.62_f32
    EYE_CROUCH    = 0.95_f32

    WALK_SPEED       =    4.6_f32
    CROUCH_SPEED     =    2.1_f32
    AIR_CONTROL      =   0.35_f32
    GRAVITY          =     24_f32
    MAX_FALL         =     55_f32
    LOOK_SENSITIVITY = 0.0022_f32
    PITCH_LIMIT      =   1.45_f32

    # Set by the game so the player only responds while a chamber is being played.
    property input_enabled = true

    # Multiplies the mouse look, and whether vertical look is inverted. Both come
    # from the settings screen and are saved between sessions.
    property sensitivity = 1.0_f32
    property invert_y = false

    # Facing, kept as yaw and pitch because mouse look is far cleaner that way.
    getter yaw = 0_f32
    getter pitch = 0_f32

    # Current eye height, which eases between standing and crouching.
    getter eye_height = EYE_STAND

    # How fast the player is currently moving, for head bob and footstep timing.
    getter horizontal_speed = 0_f32
    getter? crouching = false

    # Rises each time the footstep timer fires, so the HUD and audio can react.
    getter step_phase = 0_f32

    @crouch : Bool = false
    @shape : Physics3D::Shape
    @bob = 0_f32
    @step_timer = 0_f32

    def initialize(position : Vec3, @pair : PortalPair)
      super("player", position)
      @shape = Physics3D::Capsule.new(RADIUS, HEIGHT - RADIUS * 2)
      add_shape(@shape)
      layer = Layers::PROP
      mask = Layers::ALL & ~Layers::PROP
      floor_snap = 0.35_f32
      floor_max_angle = Mathf.deg2rad(50)
    end

    # The unit vector the player is looking along.
    def forward : Vec3
      cp = Math.cos(@pitch)
      v3(Math.sin(@yaw) * cp, Math.sin(@pitch), -Math.cos(@yaw) * cp).normalized
    end

    def right : Vec3
      v3(Math.cos(@yaw), 0, Math.sin(@yaw))
    end

    # Where the camera sits, including the head bob offset.
    def eye_position : Vec3
      v3(global_position.x, global_position.y - HEIGHT / 2 + @eye_height + bob_offset, global_position.z)
    end

    # One step of look input, in radians. Applied outside the fixed step so mouse
    # motion stays smooth regardless of the physics rate.
    def look(delta_x : Float32, delta_y : Float32) : Nil
      scale = LOOK_SENSITIVITY * @sensitivity
      @yaw += delta_x * scale
      vertical = delta_y * scale
      @pitch = (@pitch + (@invert_y ? vertical : -vertical)).clamp(-PITCH_LIMIT, PITCH_LIMIT)
      # Keep yaw bounded so it never loses precision over a long session.
      @yaw = @yaw % (Math::TAU * 2)
    end

    # Runs one fixed step: reads input, applies gravity, and moves in substeps so a
    # fast portal exit cannot tunnel through a wall.
    def step(dt : Float32) : Nil
      if @input_enabled
        look(Input.mouse_delta.x, Input.mouse_delta.y)
      end

      wish = wish_direction
      grounded = on_floor?
      update_crouch

      speed = @crouch ? CROUCH_SPEED : WALK_SPEED
      target = wish * speed
      # Ground control is instant, air control is deliberately weaker.
      accel = grounded ? 40_f32 : 40_f32 * AIR_CONTROL
      horizontal = v3(@velocity.x, 0, @velocity.z)
      horizontal = horizontal.lerp(target, (accel * dt).clamp(0_f32, 1_f32)) unless target.zero?
      horizontal = horizontal * (1.0_f32 - (10_f32 * dt).clamp(0_f32, 1_f32)) if target.zero?
      @velocity = v3(horizontal.x, @velocity.y, horizontal.z)

      @velocity.y -= GRAVITY * dt
      @velocity.y = -MAX_FALL if @velocity.y < -MAX_FALL

      move_substeps(dt)
      update_bob(dt)
      @step_phase = 0_f32
    end

    # The horizontal direction the player is asking to move in, in world space.
    private def wish_direction : Vec3
      return Vec3::ZERO unless @input_enabled
      v = Input.vector("left", "right", "forward", "back")
      dir = right * v.x + forward_flat * -v.y
      dir = v3(dir.x, 0, dir.z)
      len = dir.length
      len > 1_f32 ? dir / len : dir
    end

    # Forward flattened into the ground plane, so looking down does not slow you up.
    private def forward_flat : Vec3
      f = forward
      v3(f.x, 0, f.z).normalized
    end

    # Toggles the collider between standing and crouching. Crouching is refused when
    # there is no headroom, so the player cannot clip up into a low gap.
    private def update_crouch : Nil
      want_crouch = @input_enabled && (Input.down?(Key::LCtrl) || Input.down?(Key::C))
      if want_crouch && !@crouch
        set_crouch(true)
      elsif !want_crouch && @crouch && has_headroom?
        set_crouch(false)
      end
    end

    private def set_crouch(crouch : Bool) : Nil
      @crouch = crouch
      target = crouch ? CROUCH_HEIGHT : HEIGHT
      body.remove_shape(@shape)
      @shape = Physics3D::Capsule.new(RADIUS, target - RADIUS * 2)
      add_shape(@shape)
    end

    # True when standing up would not put the head inside geometry.
    private def has_headroom? : Bool
      feet = global_position.y - HEIGHT / 2
      space = HEIGHT - CROUCH_HEIGHT
      # A cheap vertical probe: any white or panel surface directly overhead.
      Physics3D.world.raycast(
        v3(global_position.x, feet + CROUCH_HEIGHT, global_position.z), Vec3::UP, space + 0.1_f32,
        Layers::WHITE | Layers::PANEL
      ).nil?
    end

    # Moves in chunks, testing for a portal traversal on each chunk. A traversal
    # rewrites position, velocity and facing into the destination's frame and keeps
    # whatever momentum the player had.
    private def move_substeps(dt : Float32) : Nil
      total = @velocity * dt
      steps = Math.max(1, (total.length / 0.25_f32).ceil.to_i)
      sub = dt / steps
      steps.times do
        break if total.length < 1e-6
        before = global_position
        move_and_slide(sub, @velocity)
        if @pair.linked? && check_portals(before, global_position)
          break # the rest of this step is spent moving in the new frame
        end
      end
    end

    # Tests the swept segment against both portals and teleports if one is crossed.
    private def check_portals(from : Vec3, to : Vec3) : Bool
      blue = @pair.blue.placement
      orange = @pair.orange.placement
      if blue && orange
        if Teleport.crosses?(from, to, blue, orange)
          apply_teleport(blue, orange)
          return true
        end
        if Teleport.crosses?(from, to, orange, blue)
          apply_teleport(orange, blue)
          return true
        end
      end
      false
    end

    # Moves the player from one opening to the other, preserving momentum and
    # carrying the view direction across.
    def apply_teleport(src : Placement, dst : Placement) : Nil
      before = global_position
      new_pos = Teleport.point(src, dst, before)
      new_vel = Teleport.direction(src, dst, @velocity)
      new_forward = Teleport.direction(src, dst, forward)

      @velocity = new_vel
      # Step clear of the destination plane so the player is not re-tested next frame.
      self.global_position = new_pos + dst.normal * 0.06_f32
      set_facing(new_forward)
    end

    # Re-derives yaw and pitch from a world-space direction, so look survives a jump.
    def set_facing(direction : Vec3) : Nil
      d = direction.normalized
      @pitch = Math.asin(d.y.clamp(-1_f32, 1_f32))
      @yaw = Math.atan2(d.x, -d.z)
    end

    # Head bob and footsteps. The bob follows distance travelled, not time, so it
    # stays in step with the player's actual speed.
    private def update_bob(dt : Float32) : Nil
      horizontal = v3(@velocity.x, 0, @velocity.z)
      @horizontal_speed = horizontal.length
      if on_floor? && @horizontal_speed > 0.4
        @bob += @horizontal_speed * dt * 1.9_f32
        @step_timer += dt * (@horizontal_speed / WALK_SPEED)
        if @step_timer >= 0.5
          @step_timer -= 0.5
          @step_phase = 1_f32
        end
      else
        @step_timer = 0.42_f32
      end
      target = @crouch ? EYE_CROUCH : EYE_STAND
      @eye_height += (target - @eye_height) * (14_f32 * dt).clamp(0_f32, 1_f32)
    end

    # The vertical part of the head bob, applied to the camera only.
    def bob_offset : Float32
      return 0_f32 unless on_floor? && @horizontal_speed > 0.4
      (Math.sin(@bob * 2_f32) * 0.022_f32 + Math.sin(@bob) * 0.012_f32)
    end

    # A small sideways figure-eight, applied to the camera only.
    def bob_roll : Float32
      return 0_f32 unless on_floor? && @horizontal_speed > 0.4
      Math.cos(@bob) * 0.006_f32
    end

    # The camera's up vector, tilted slightly by the head bob so the roll reads.
    def up_hint : Vec3
      Quat.from_axis_angle(forward, bob_roll) * Vec3::UP
    end

    # Drops the player onto the ground below, used on respawn.
    def teleport_to(position : Vec3, facing : Vec3 = v3(0, 0, -1)) : Nil
      self.global_position = position
      @velocity = Vec3::ZERO
      set_facing(facing)
    end
  end
end
