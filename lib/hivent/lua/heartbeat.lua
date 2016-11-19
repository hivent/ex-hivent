local service_name  = ARGV[1]
local consumer_name = ARGV[2]
local CONSUMER_TTL  = ARGV[3]

local function keepalive(service, consumer)
  redis.call("SET", service .. ":" .. consumer .. ":alive", "true", "PX", CONSUMER_TTL)
  redis.call("SADD", service .. ":consumers", consumer)
end

local function cleanup(service)
  local consumer_index_key = service .. ":consumers"
  local consumers = redis.call("SMEMBERS", consumer_index_key)

  for _, consumer in ipairs(consumers) do
    local consumer_status_key = service .. ":" .. consumer .. ":alive"
    local alive = redis.call("GET", consumer_status_key)

    if not alive then
      redis.call("SREM", consumer_index_key, consumer)
    end
  end
end

local function heartbeat(service_name, consumer_name)
  -- keep consumer alive
  keepalive(service_name, consumer_name)

  -- clean up dead consumers
  cleanup(service_name)

  return true
end

return heartbeat(service_name, consumer_name)