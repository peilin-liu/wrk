
-- 4T / 256k
local max = 16 * 1000 * 1000

-- 50G / 256k
local hot = 200 * 1000

math.randomseed(os.time())

wrk.scheme  = "http"
wrk.host    = "192.168.3.137"
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

function setup(thread, cs)
   print(string.format("setup cs=%d",cs))
   thread:set("id", counter)
   thread:set("connections", tonumber(cs))
   --print(string.format("setup connections=%d",connections))
   thread:set("request_count", 0);
   table.insert(threads, thread)
   counter = counter + 1
   local msg = "setup id=%d, sc=%d, rc=%d\n"
   print(msg:format(thread:get("id"), thread:get("connections"), thread:get("request_count")))
end


function init(args)
   requests  = 0
   responses = 0

   local msg = "thread %d / %d created"
   print(msg:format(id, wrk.parallel_worker))
end

function getlcm(m , n)
	local a = m
	local b = n
	while a~=b do
	   if a>b then  
		 a=a-b      
       else  
		 b=b-a
	   end
	end 
	return (m*n)/a
end

request = function(key)
	local lcm = getlcm(wrk.parallel_worker, connections)
    local localhot = hot - hot % lcm
    local rand = math.random(localhot, max)
    local single_hot = 0
    if rand % 100 < 80 then
        single_hot = math.floor(localhot/wrk.parallel_worker)
		rand = single_hot*(id-1)
		local single_pos = single_hot - single_hot%connections
        rand = rand + single_pos + key

        headers["Oct-expires-default"] = "864000"
    else
        headers["Oct-expires-default"] = "100"
        rand = rand + hot
    end
 
    num = num + 1
    -- rand = num

    path = "/" .. rand
	local msg = "request spec %d/%d %-6d %-8d/%4d %8d/%4d created"
	print(msg:format(id, wrk.parallel_worker, single_hot, rand, key,localhot, lcm))
    return wrk.format("GET", path, headers)
end

--delay = function ()
--    return 20
    --return math.random(1, 500)
--end
