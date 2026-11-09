-- WePlay: Trains Get Radar
-- Every locomotive charts the chunks around it. Work is spread across ticks,
-- parked trains refresh slowly, and chunks charted recently are skipped so
-- overlapping trains (busy stations, multi-loco trains) share the cost.

local CHUNK = 32
local KEY_SCALE = 65536        -- chunk coords stay well under +/-32768
local PRUNE_TICKS = 36000      -- wipe the chunk timestamp cache every 10 minutes

local cfg = {}

local function read_settings()
  local g = settings.global
  cfg.radius = g["wp-trains-radar-radius"].value
  cfg.interval = g["wp-trains-radar-interval"].value
  cfg.parked = g["wp-trains-radar-parked-interval"].value * 60
end

local function init_storage()
  storage.list = storage.list or {}        -- array of { entity, unit, last }
  storage.tracked = storage.tracked or {}  -- [unit_number] = true
  storage.index = storage.index or 1
  storage.stamps = storage.stamps or {}    -- [force][surface][chunk_key] = tick
  storage.last_prune = storage.last_prune or 0
end

local function track(entity)
  if not (entity and entity.valid and entity.type == "locomotive") then return end
  local unit = entity.unit_number
  if not unit or storage.tracked[unit] then return end
  storage.tracked[unit] = true
  local list = storage.list
  list[#list + 1] = { entity = entity, unit = unit, last = nil }
end

local function track_train(train)
  if not (train and train.valid) then return end
  local locos = train.locomotives
  for _, loco in pairs(locos.front_movers) do track(loco) end
  for _, loco in pairs(locos.back_movers) do track(loco) end
end

local function rebuild()
  storage.list = {}
  storage.tracked = {}
  storage.index = 1
  storage.stamps = {}
  for _, surface in pairs(game.surfaces) do
    for _, loco in pairs(surface.find_entities_filtered({ type = "locomotive" })) do
      track(loco)
    end
  end
end

local function chart_around(rec, tick)
  local entity = rec.entity
  local surface = entity.surface
  local force = entity.force
  local pos = entity.position
  local cx = math.floor(pos.x / CHUNK)
  local cy = math.floor(pos.y / CHUNK)
  local r = cfg.radius
  local fresh = cfg.interval

  local by_force = storage.stamps[force.index]
  if not by_force then
    by_force = {}
    storage.stamps[force.index] = by_force
  end
  local stamps = by_force[surface.index]
  if not stamps then
    stamps = {}
    by_force[surface.index] = stamps
  end

  for x = cx - r, cx + r do
    for y = cy - r, cy + r do
      local key = x * KEY_SCALE + y
      local t = stamps[key]
      if not t or tick - t >= fresh then
        stamps[key] = tick
        local x0, y0 = x * CHUNK, y * CHUNK
        force.chart(surface, { { x0 + 1, y0 + 1 }, { x0 + CHUNK - 1, y0 + CHUNK - 1 } })
      end
    end
  end
  rec.last = tick
end

local function on_tick(event)
  local list = storage.list
  local n = #list
  if n == 0 then return end

  local tick = event.tick
  local parked = cfg.parked
  local budget = math.ceil(n / cfg.interval)
  local idx = storage.index

  while budget > 0 and n > 0 do
    if idx > n then
      idx = 1
      if tick - storage.last_prune >= PRUNE_TICKS then
        storage.stamps = {}
        storage.last_prune = tick
      end
    end

    local rec = list[idx]
    local entity = rec.entity
    if not entity.valid then
      -- swap-remove dead locomotives; don't advance idx
      storage.tracked[rec.unit] = nil
      list[idx] = list[n]
      list[n] = nil
      n = n - 1
    else
      local train = entity.train
      local moving = train and train.speed ~= 0
      if moving or (parked > 0 and (not rec.last or tick - rec.last >= parked)) then
        chart_around(rec, tick)
      end
      idx = idx + 1
    end
    budget = budget - 1
  end

  storage.index = idx
end

-- Lifecycle -------------------------------------------------------------------

script.on_init(function()
  init_storage()
  read_settings()
  rebuild()
end)

script.on_configuration_changed(function()
  init_storage()
  read_settings()
  rebuild()
end)

script.on_load(function()
  read_settings()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function()
  read_settings()
end)

-- Tracking --------------------------------------------------------------------

local filters = { { filter = "type", type = "locomotive" } }

local function on_built(event)
  track(event.entity)
end

script.on_event(defines.events.on_built_entity, on_built, filters)
script.on_event(defines.events.on_robot_built_entity, on_built, filters)
script.on_event(defines.events.script_raised_built, on_built, filters)
script.on_event(defines.events.script_raised_revive, on_built, filters)
script.on_event(defines.events.on_entity_cloned, function(event)
  track(event.destination)
end, filters)

-- Catches locomotives made by other mods' scripts that don't raise build
-- events (shuttle/taxi mods, space elevators, etc.).
script.on_event(defines.events.on_train_created, function(event)
  track_train(event.train)
end)

script.on_event(defines.events.on_tick, on_tick)

-- Remote interface: lets other mods or the console force a full rescan.
remote.add_interface("WePlayTrainsGetRadar", {
  rebuild = rebuild,
  count = function() return #storage.list end
})
