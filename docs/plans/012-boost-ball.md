# 012 Boost Ball (rocket-powered car soccer example)

Status: implemented, on the site as `rocketball`.

A complete car-soccer game built only on Eagle, as a large end-to-end test of the 3D renderer, audio, UI drawing and web backend.

## Layout

- `physics.cr`: arena boxes and corner bevels, ball, car (drive, boost, jump, flip, air control, landing).
- `bot.cr`: computer drivers with attack, support and defend roles and three skill levels.
- `match.cr`: kickoff countdown, clock, overtime, goals, assists, saves, boost pads, demolitions, goal replay.
- `menu.cr`: renderer-independent menu model (buttons, choices, sliders).
- `stage.cr`, `audio.cr`, `main.cr`: scenery, car models, particles, synthesized sound and music, screens and HUD.
- `spec/examples/rocketball_spec.cr`: physics, match rules, bot-vs-bot soak and menu specs.

## Screens

Title (live bot match behind it), match setup, settings, controls, pause, results, free play.

## Known gaps

No wall or ceiling driving, no air dribbling for bots, settings are not saved to disk, gamepad play is untested on hardware.
