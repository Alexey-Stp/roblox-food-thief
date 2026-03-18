-- RestaurantBuilder_spec.lua
-- Tests for RestaurantBuilder.lua: stair geometry, floor-slab openings,
-- elevator call buttons, restaurant interior elements, and build() structure.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function loadConfig()
	package.loaded["src.server.modules.Config"] = nil
	return require("src.server.modules.Config")
end

local function loadBuilder()
	resetServices()
	resetWorkspace()
	package.loaded["src.server.modules.RestaurantBuilder"] = nil
	return require("src.server.modules.RestaurantBuilder")
end

-- Collect all instances parented anywhere under workspace that match a predicate.
local function findAll(predicate)
	local results = {}
	local function recurse(obj)
		for _, c in ipairs(obj._children) do
			if predicate(c) then
				table.insert(results, c)
			end
			if c._children then
				recurse(c)
			end
		end
	end
	recurse(workspace)
	return results
end

-- Collect all instances with a given Name prefix.
local function findByNamePrefix(prefix)
	return findAll(function(c) return string.sub(c.Name, 1, #prefix) == prefix end)
end

-- Return the first instance matching a name exactly.
local function findFirst(name)
	local all = findAll(function(c) return c.Name == name end)
	return all[1]
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("RestaurantBuilder", function()

	-- -----------------------------------------------------------------------
	-- Staircase geometry
	-- -----------------------------------------------------------------------
	describe("staircase geometry", function()

		it("each staircase uses exactly 12 steps", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			-- Steps are named e.g. "Stairs_F1_F2_Step1" ... "Stairs_F1_F2_Step12"
			local f1Steps = findByNamePrefix("Stairs_F1_F2_Step")
			assert.equals(12, #f1Steps, "F1→F2 staircase should have exactly 12 steps")

			local f2Steps = findByNamePrefix("Stairs_F2_F3_Step")
			assert.equals(12, #f2Steps, "F2→F3 staircase should have exactly 12 steps")
		end)

		it("step height × step count does not exceed FLOOR_HEIGHT", function()
			local Config = loadConfig()
			-- STAIR constants: 12 steps × 2 studs each = 24 studs
			local STEP_COUNT = 12
			local STEP_HEIGHT = 2
			assert.is_true(
				STEP_COUNT * STEP_HEIGHT <= Config.FLOOR_HEIGHT,
				("steps climb %d studs but FLOOR_HEIGHT is only %d"):format(
					STEP_COUNT * STEP_HEIGHT,
					Config.FLOOR_HEIGHT
				)
			)
		end)

		it("F1→F2 staircase has a landing Part", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local landing = findFirst("Stairs_F1_F2_Landing")
			assert.not_nil(landing, "F1→F2 staircase should have a landing Part")
			assert.is_true(landing.Anchored, "landing should be anchored")
		end)

		it("F2→F3 staircase has a landing Part", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local landing = findFirst("Stairs_F2_F3_Landing")
			assert.not_nil(landing, "F2→F3 staircase should have a landing Part")
		end)

		it("stair steps are placed at increasing Y positions", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			-- Collect F1→F2 steps and verify ascending Y
			local steps = {}
			for i = 1, 12 do
				local s = findFirst("Stairs_F1_F2_Step" .. i)
				assert.not_nil(s, "missing step " .. i)
				table.insert(steps, s)
			end

			for i = 2, #steps do
				assert.is_true(
					steps[i].Position.Y > steps[i - 1].Position.Y,
					("step %d Y (%g) should be greater than step %d Y (%g)"):format(
						i,
						steps[i].Position.Y,
						i - 1,
						steps[i - 1].Position.Y
					)
				)
			end
		end)

		it("top of last F1→F2 step does not exceed F2 slab Y", function()
			local Config = loadConfig()
			-- STAIR_STEP_COUNT=12, STAIR_STEP_HEIGHT=2, startY = cy + 0.5
			-- Zero-indexed loop: last step is i=11 (STEP_COUNT-1).
			-- Its top face = startY + (STEP_COUNT-1)*STEP_HEIGHT + STEP_HEIGHT
			--              = startY + STEP_COUNT * STEP_HEIGHT  (simplified)
			local GEOMETRY_TOLERANCE = 0.01 -- floating-point tolerance for geometry comparisons (studs)
			local cy = Config.HOTEL_CENTER.Y
			local fh = Config.FLOOR_HEIGHT
			local startY = cy + 0.5
			local STEP_COUNT = 12
			local STEP_HEIGHT = 2
			-- Top face of the last step (step i = STEP_COUNT-1 in the 0-based loop):
			--   centre Y = startY + (STEP_COUNT-1)*STEP_HEIGHT + STEP_HEIGHT/2
			--   top face = centre Y + STEP_HEIGHT/2 = startY + STEP_COUNT * STEP_HEIGHT
			local lastStepTopY = startY + STEP_COUNT * STEP_HEIGHT
			-- F2 slab bottom face (slab centred at cy+fh, height 1 → bottom at cy+fh-0.5)
			local slabBottomY = cy + fh - 0.5
			assert.is_true(
				lastStepTopY <= slabBottomY + GEOMETRY_TOLERANCE,
				("last step top Y (%g) must be at or below slab bottom Y (%g)"):format(
					lastStepTopY,
					slabBottomY
				)
			)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Floor-slab openings (buildSlabWithOpenings)
	-- -----------------------------------------------------------------------
	describe("floor slabs", function()

		it("floor slab parts exist after build()", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local slabs = findByNamePrefix("Slab")
			assert.is_true(#slabs > 0, "expected floor slab parts to be created")
		end)

		it("each slab Part is anchored and uses concrete material", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local slabs = findByNamePrefix("Slab")
			for _, s in ipairs(slabs) do
				assert.is_true(s.Anchored, "slab " .. s.Name .. " should be anchored")
				-- Enum mock returns "Material.Concrete" (without "Enum." prefix)
				assert.equals(
					"Material.Concrete",
					tostring(s.Material),
					"slab " .. s.Name .. " should use Concrete material"
				)
			end
		end)

		it("no slab part occupies the lift shaft centre position", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local cx = Config.HOTEL_CENTER.X
			local cz = Config.HOTEL_CENTER.Z
			local hw = Config.HOTEL_SIZE.X / 2
			local liftEX = cx + hw - 25
			local tolerance = 8 -- half of shaft opening

			local slabs = findByNamePrefix("Slab1") -- F1→F2 slab
			for _, s in ipairs(slabs) do
				local sx = s.Position.X
				local sz = s.Position.Z
				local inShaftX = sx > liftEX - tolerance and sx < liftEX + tolerance
				local inShaftZ = sz > cz - tolerance and sz < cz + tolerance
				assert.is_false(
					inShaftX and inShaftZ,
					"slab part at (" .. sx .. "," .. sz .. ") overlaps with east lift shaft centre"
				)
			end
		end)

		it("no slab part occupies the F1→F2 staircase opening centre", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local cx = Config.HOTEL_CENTER.X
			local cz = Config.HOTEL_CENTER.Z
			-- Stair centre: X ≈ cx-50+12, Z = cz+130
			local stairCX = cx - 50 + 12
			local stairCZ = cz + 130
			local tol = 8

			local slabs = findByNamePrefix("Slab1")
			for _, s in ipairs(slabs) do
				local sx = s.Position.X
				local sz = s.Position.Z
				local inStairX = sx > stairCX - tol and sx < stairCX + tol
				local inStairZ = sz > stairCZ - tol and sz < stairCZ + tol
				assert.is_false(
					inStairX and inStairZ,
					"slab part at (" .. sx .. "," .. sz .. ") overlaps with F1→F2 stair opening"
				)
			end
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Elevator call buttons
	-- -----------------------------------------------------------------------
	describe("elevator call buttons", function()

		it("east lift has two call button Parts (one per served floor)", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local btns = findByNamePrefix("LiftCallBtn_east")
			assert.equals(2, #btns, "east lift should have exactly 2 call buttons")
		end)

		it("west lift has two call button Parts", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local btns = findByNamePrefix("LiftCallBtn_west")
			assert.equals(2, #btns, "west lift should have exactly 2 call buttons")
		end)

		it("each call button has a ProximityPrompt child", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local btns = findByNamePrefix("LiftCallBtn_")
			assert.is_true(#btns > 0, "expected call buttons to exist")
			for _, btn in ipairs(btns) do
				local prompt = nil
				for _, child in ipairs(btn._children) do
					if child.ClassName == "ProximityPrompt" then
						prompt = child
					end
				end
				assert.not_nil(prompt, "call button " .. btn.Name .. " should have a ProximityPrompt")
				assert.equals("Call Lift", prompt.ActionText)
			end
		end)

		it("call buttons are not collidable (CanCollide = false)", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local btns = findByNamePrefix("LiftCallBtn_")
			for _, btn in ipairs(btns) do
				assert.is_false(btn.CanCollide, btn.Name .. " should have CanCollide = false")
			end
		end)

		it("triggering a call button does not error when lift is not moving", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local btns = findByNamePrefix("LiftCallBtn_east")
			assert.is_true(#btns > 0, "expected at least one east call button")

			local btn = btns[1]
			local prompt = nil
			for _, child in ipairs(btn._children) do
				if child.ClassName == "ProximityPrompt" then
					prompt = child
				end
			end
			assert.not_nil(prompt)

			-- Firing should complete without error (task.spawn is a no-op in tests)
			assert.has_no.errors(function()
				prompt.Triggered._fire(prompt.Triggered, { Name = "TestPlayer" })
			end)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Restaurant interior elements
	-- -----------------------------------------------------------------------
	describe("restaurant interior", function()

		it("build() creates dining chairs for each floor", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			-- There should be chairs on every floor
			for f = 1, Config.FLOOR_COUNT do
				local chairs = findAll(function(c)
					return string.sub(c.Name, 1, #("Chair_F" .. f)) == "Chair_F" .. f
				end)
				assert.is_true(
					#chairs > 0,
					"floor " .. f .. " should have at least one chair"
				)
			end
		end)

		it("each floor has a bar counter", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			for f = 1, Config.FLOOR_COUNT do
				local bar = findFirst("BarCounter_F" .. f)
				assert.not_nil(bar, "floor " .. f .. " should have a BarCounter Part")
				assert.is_true(bar.Anchored)
			end
		end)

		it("each floor has wall paintings", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			for f = 1, Config.FLOOR_COUNT do
				local paintings = findAll(function(c)
					return string.sub(c.Name, 1, #("Painting_F" .. f)) == "Painting_F" .. f
				end)
				assert.is_true(
					#paintings > 0,
					"floor " .. f .. " should have at least one wall painting"
				)
			end
		end)

		it("tables have a food position entry for each table", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local _, positions = RB.build(Config)

			for f = 1, Config.FLOOR_COUNT do
				assert.not_nil(positions[f], "floor " .. f .. " food positions should not be nil")
				assert.equals(
					Config.TABLES_PER_FLOOR[f],
					#positions[f],
					("floor %d should have %d food positions"):format(f, Config.TABLES_PER_FLOOR[f])
				)
			end
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Exterior environment
	-- -----------------------------------------------------------------------
	describe("exterior environment", function()

		it("build() creates an entrance path", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local pathParts = findByNamePrefix("EntrancePath_")
			assert.is_true(#pathParts > 0, "expected entrance path segments to be created")
		end)

		it("entrance path parts are cobblestone", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local pathParts = findByNamePrefix("EntrancePath_")
			for _, p in ipairs(pathParts) do
				-- Enum mock returns "Material.Cobblestone" (without "Enum." prefix)
				assert.equals(
					"Material.Cobblestone",
					tostring(p.Material),
					p.Name .. " should use Cobblestone material"
				)
			end
		end)

		it("build() creates a river Part", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local river = findFirst("River")
			assert.not_nil(river, "expected a River Part to be created")
			assert.is_true(river.Transparency > 0, "river should be semi-transparent")
			assert.is_false(river.CanCollide, "river should not be collidable")
		end)

		it("build() creates hill Parts", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			RB.build(Config)

			local hills = findAll(function(c) return c.Name == "Hill" end)
			assert.is_true(#hills > 0, "expected at least one Hill Part to be created")
		end)
	end)

	-- -----------------------------------------------------------------------
	-- build() return value contract
	-- -----------------------------------------------------------------------
	describe("build() contract", function()

		it("returns a hotel Model and floor food positions table", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local hotel, positions = RB.build(Config)

			assert.not_nil(hotel, "build() should return the hotel model")
			assert.equals("Model", hotel.ClassName)
			assert.not_nil(positions, "build() should return floorFoodPositions")
		end)

		it("hotel is parented to workspace", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local hotel = RB.build(Config)

			local found = workspace:FindFirstChild("GrandHotel")
			assert.not_nil(found, "GrandHotel model should be in workspace")
		end)

		it("floorFoodPositions has one sub-table per floor", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local _, positions = RB.build(Config)

			assert.equals(Config.FLOOR_COUNT, #positions)
		end)

		it("each floorFoodPositions entry has the expected count", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local _, positions = RB.build(Config)

			for f = 1, Config.FLOOR_COUNT do
				assert.equals(
					Config.TABLES_PER_FLOOR[f],
					#positions[f],
					("floor %d should have %d entries"):format(f, Config.TABLES_PER_FLOOR[f])
				)
			end
		end)

		it("each food position entry has a position and foodType", function()
			local RB = loadBuilder()
			local Config = loadConfig()
			local _, positions = RB.build(Config)

			for f = 1, Config.FLOOR_COUNT do
				for _, entry in ipairs(positions[f]) do
					assert.not_nil(entry.position, "food position entry must have a position")
					assert.not_nil(entry.foodType, "food position entry must have a foodType")
					assert.not_nil(entry.foodType.name)
					assert.not_nil(entry.foodType.sellPrice)
				end
			end
		end)
	end)

end)
