require "../spec_helper"
require "../../examples/voxel/world"

describe EagleVoxel::Island do
  it "generates a stable island from a seed" do
    a = EagleVoxel::Island.new(2026)
    b = EagleVoxel::Island.new(2026)
    c = EagleVoxel::Island.new(7)
    a.occupied.should eq b.occupied
    a.occupied.should be > 800
    a.occupied.should be < EagleVoxel::Island::VOLUME
    a.occupied.should_not eq c.occupied
    a.cells.to_a.should eq b.cells.to_a
  end

  it "spawns the player on solid ground inside the island" do
    island = EagleVoxel::Island.new(2026)
    feet = island.spawn
    island.in_bounds?(feet.x.to_i, (feet.y - 0.5).to_i, feet.z.to_i).should be_true
    island.solid?(feet.x.floor.to_i, (feet.y - 0.2).floor.to_i, feet.z.floor.to_i).should be_true
    island.solid?(feet.x.floor.to_i, feet.y.floor.to_i + 1, feet.z.floor.to_i).should be_false
  end

  it "greedy-meshes a single voxel as six quads" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island[4, 5, 6] = EagleVoxel::STONE
    mesh = island.build_mesh
    island.mesh_quads.should eq 6
    mesh.triangle_count.should eq 12
    mesh.vertex_count.should eq 24
  end

  it "merges coplanar faces of the same colour" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island[3, 4, 5] = EagleVoxel::GRASS
    island[4, 4, 5] = EagleVoxel::GRASS
    island.build_mesh
    island.mesh_quads.should eq 6
  end

  it "does not merge faces of different colours" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island[3, 4, 5] = EagleVoxel::GRASS
    island[4, 4, 5] = EagleVoxel::STONE
    island.build_mesh
    island.mesh_quads.should eq 10
  end

  it "hits a voxel with a DDA ray and reports the entry face" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island[5, 5, 5] = EagleVoxel::DIRT
    hit = island.raycast(v3(5.5, 5.5, 2), v3(0, 0, 1), 10).not_nil!
    hit.voxel.should eq({5, 5, 5})
    hit.nz.should eq(-1)
    hit.place.should eq({5, 5, 4})
    island.raycast(v3(5.5, 5.5, 2), v3(0, 0, -1), 10).should be_nil
  end

  it "breaks and places against the hit face, refusing overlap with the player" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island[5, 1, 5] = EagleVoxel::STONE
    hit = island.raycast(v3(5.5, 1.5, 2), v3(0, 0, 1), 10).not_nil!
    island.break_at(hit).should eq EagleVoxel::STONE
    island.solid?(5, 1, 5).should be_false

    island[5, 1, 5] = EagleVoxel::STONE
    hit = island.raycast(v3(5.5, 1.5, 2), v3(0, 0, 1), 10).not_nil!
    island.place_at(hit, EagleVoxel::BRICK, v3(5.5, 1.0, 3.5), 0.28, 1.7).should be_true
    island[5, 1, 4].should eq EagleVoxel::BRICK

    island[5, 1, 4] = 0_u8
    island.place_at(hit, EagleVoxel::BRICK, v3(5.5, 1.0, 4.2), 0.28, 1.7).should be_false
  end

  it "slides AABB movement along walls and stands on floors" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    8.times { |x| 8.times { |z| island[x, 0, z] = EagleVoxel::STONE } }
    island[4, 1, 4] = EagleVoxel::STONE
    feet, vel, grounded = island.move(v3(2.5, 1.01, 2.5), v3(0, -4, 0), 0.05_f32, 0.28, 1.7)
    grounded.should be_true
    vel.y.should eq 0
    feet.y.should be_close(1.01, 0.05)

    blocked = island.move(v3(3.2, 1.01, 4.5), v3(4, 0, 0), 0.16_f32, 0.28, 1.7)
    blocked[0].x.should be < 3.8
    blocked[1].x.should eq 0
  end

  it "stamps every placeable colour" do
    island = EagleVoxel::Island.new(1)
    island.cells.fill(0_u8)
    island.stamp_palette(2, 3, 4)
    (1...EagleVoxel::PALETTE.size).each do |i|
      island[2 + (i - 1) % 4, 3, 4 + (i - 1) // 4].should eq i.to_u8
    end
  end
end
