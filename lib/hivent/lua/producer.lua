local event        = ARGV[1]
local payload      = ARGV[2]
local partition_id = ARGV[3]

local function concat_tables_uniq(table1, table2)
  for i=1, #table2 do table.insert(table1, table2[i]) end
  local set = {}
  for _, l in ipairs(table1) do set[l] = true end
  local uniq = {}
  for i, _ in pairs(set) do table.insert(uniq, i) end
  return uniq
end

local function produce(event, payload, partition_id)
  local consumers = concat_tables_uniq(redis.call("SMEMBERS", event), redis.call("SMEMBERS", "*"))

  for _, consumer in ipairs(consumers) do
    local partition_count = tonumber(redis.call("GET", consumer .. ":partition_count"))
    local partition = partition_id % partition_count
    local queue = consumer .. ":" .. partition

    redis.call("LPUSH", queue, payload)
  end

end

produce(event, payload, tonumber(partition_id))