
-- 4T / 256k
local max = 16 * 1000 * 1000

-- 50G / 256k
local hot = 200 * 1000

math.randomseed(os.time())

wrk.scheme  = "http"
wrk.host    = "192.168.3.20"
wrk.port    = 8000
wrk.method  = "GET"

headers = {
    ["Host"] = "test.com",
    ["Oct-Host"] = "127.0.0.1",
    ["Oct-expires-default"] = "864000",
}

num = 0

local counter = 1
local threads = {}

function setup(thread)
   thread:set("id", counter)
   table.insert(threads, thread)
   counter = counter + 1
end


function init(args)
   requests  = 0
   responses = 0

   local msg = "thread %d / %d created"
   print(msg:format(id, wrk.parallel_worker))
end

request = function()
    local rand = math.random(hot, max)
    if rand % 100 < 80 then
        rand = rand % hot
        headers["Oct-expires-default"] = "864000"

    else
        headers["Oct-expires-default"] = "100"
    end

    num = num + 1
    -- rand = num

    path = "/" .. rand
    return wrk.format("GET", path, headers)
end

-- delay = function ()
--     return 20
--    --return math.random(1, 500)
-- end
