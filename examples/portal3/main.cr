require "../../src/eagle"
require "./portal3"

# Portal 3 is a first-person puzzle game. The device in your hand opens a linked pair of
# portals on white panels, and everything else follows from that: weighted cubes,
# buttons, doors, lifts, sentry turrets, lasers and a pit of toxic liquid. Nineteen
# chambers teach the pieces and then combine them.
#
# Everything you see and hear is generated at runtime. There are no asset files: the
# panel and hazard textures are drawn into images at startup, and every sound is
# synthesised, so the whole game ships as a single executable.
Eagle.run(Portal3::Game,
  title: "Portal 3",
  width: 1600,
  height: 900,
  msaa: 4,
  vsync: true)
