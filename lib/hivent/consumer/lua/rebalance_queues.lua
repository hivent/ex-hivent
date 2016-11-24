local service_name  = ARGV[1]
local consumer_name = ARGV[2]
local CONSUMER_TTL  = ARGV[3]

-- Performs deep equality between two tables
local function table_eq(table1, table2)
 local avoid_loops = {}
 local function recurse(t1, t2)
  -- compare value types
  if type(t1) ~= type(t2) then return false end
  -- Base case: compare simple values
  if type(t1) ~= "table" then return t1 == t2 end
  -- Now, on to tables.
  -- First, let's avoid looping forever.
  if avoid_loops[t1] then return avoid_loops[t1] == t2 end
  avoid_loops[t1] = t2
  -- Copy keys from t2
  local t2keys = {}
  local t2tablekeys = {}
  for k, _ in pairs(t2) do
     if type(k) == "table" then table.insert(t2tablekeys, k) end
     t2keys[k] = true
  end
  -- Let's iterate keys from t1
  for k1, v1 in pairs(t1) do
     local v2 = t2[k1]
     if type(k1) == "table" then
        -- if key is a table, we need to find an equivalent one.
        local ok = false
        for i, tk in ipairs(t2tablekeys) do
           if table_eq(k1, tk) and recurse(v1, t2[tk]) then
              table.remove(t2tablekeys, i)
              t2keys[tk] = nil
              ok = true
              break
           end
        end
        if not ok then return false end
     else
        -- t1 has a key which t2 doesn't have, fail.
        if v2 == nil then return false end
        t2keys[k1] = nil
        if not recurse(v1, v2) then return false end
     end
  end
  -- if t2 has a key which t1 doesn't have, fail.
  if next(t2keys) then return false end
  return true
 end
 return recurse(table1, table2)
end

local function distribute(consumers, partition_count)
  local distribution   = {}
  local consumer_count = table.getn(consumers)
  local remainder      = partition_count % consumer_count

  for i=1,consumer_count do
    distribution[i] = math.floor(partition_count/consumer_count)
  end

  for i=1,remainder do
    distribution[i] = distribution[i] + 1
  end

  return distribution
end

local function getdesiredstate(service_name, consumers, partition_count)
  local state                    = {}
  local distribution             = distribute(consumers, partition_count)
  local consumer_count           = table.getn(consumers)
  local assigned_partition_count = 0

  for i=1,consumer_count do
    state[consumers[i]] = {}

    for j=1,distribution[i] do
      table.insert(state[consumers[i]], 1, service_name .. ":" .. j + assigned_partition_count - 1)
    end

    assigned_partition_count = assigned_partition_count + distribution[i]
  end

  return state
end

local function getcurrentstate(service_name, consumers)
  local state = {}

  for _, consumer in ipairs(consumers) do
    local assigned_key = service_name .. ":" .. consumer .. ":assigned"
    state[consumer] = redis.call("LRANGE", assigned_key, 0, -1)
  end

  return state
end

local function states_match(state1, state2)
  return table_eq(state1, state2)
end

local function all_free(workers)
  local total_count = 0

  for _, partitions in pairs(workers) do
    total_count = total_count + table.getn(partitions)
  end

  return total_count == 0
end

local function save_state(service_name, state)
  for worker, partitions in pairs(state) do
    for _, partition in ipairs(partitions) do
      redis.call("RPUSH", service_name .. ":" .. worker .. ":assigned", partition)
      redis.call("EXPIRE", service_name .. ":" .. worker .. ":assigned", CONSUMER_TTL)
    end
  end
end

local function rebalance(service_name, consumer_name)
  local consumers = redis.call("SMEMBERS", service_name .. ":consumers")
  table.sort(consumers)
  local partition_count = tonumber(redis.call("GET", service_name .. ":partition_count"))

  local desired_state = getdesiredstate(service_name, consumers, partition_count)

  local current_state = getcurrentstate(service_name, consumers)

  local is_stable_state = states_match(desired_state, current_state)

  if not is_stable_state then
    if all_free(current_state) then
      save_state(service_name, desired_state)

      return desired_state[consumer_name]
    else
      redis.call("DEL", service_name .. ":" .. consumer_name .. ":assigned")
      return {}
    end
  else
    return desired_state[consumer_name]
  end
end

return rebalance(service_name, consumer_name)
