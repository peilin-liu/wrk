-- Complex scenario script for multi-rule rate-limit testing.
--
-- Usage:
--   wrk -t2 -c20 -d30s -s scripts/custom/complex_scenarios.lua http://127.0.0.1:8080
--
-- Scenario config:
--   scripts/custom/cfg/scenarios_cfg.lua
--
-- Each scenario's target_qps is split by thread count and scheduled with
-- delay(). wrk.now() supplies millisecond time from the C layer.

local scenarios = require("scripts.custom.cfg.scenarios_cfg")

local scenario_runner = {
   scenarios = {},
   by_name = {},
   stats = {},
   inflight = {},
   reservations = {},
   reservations_by_key = {},
   threads = {},
   total_target_qps = 0,
   latency = {
      buckets = {},
      total_cost = 0,
      total_count = 0,
      last_sec = nil,
   },
}

local LATENCY_BUCKETS = 11

local function now_ms()
   return wrk.now()
end

local function clone_headers(headers)
   local copy = {}
   for name, value in pairs(wrk.headers) do
      copy[name] = value
   end
   for name, value in pairs(headers or {}) do
      copy[name] = value
   end
   return copy
end

local function encode_query_value(value)
   value = tostring(value)
   value = value:gsub("\n", "\r\n")
   value = value:gsub("([^%w%-%_%.%~])", function(c)
      return string.format("%%%02X", string.byte(c))
   end)
   return value
end

local function append_params(path, params)
   if not params then return path end

   local query = {}
   for name, value in pairs(params) do
      query[#query + 1] = encode_query_value(name) .. "=" .. encode_query_value(value)
   end

   if #query == 0 then return path end

   local sep = path:find("?", 1, true) and "&" or "?"
   return path .. sep .. table.concat(query, "&")
end

local function append_cookies(headers, cookies)
   if not cookies then return end

   local values = {}
   if headers["Cookie"] then
      values[#values + 1] = headers["Cookie"]
   end

   for name, value in pairs(cookies) do
      values[#values + 1] = tostring(name) .. "=" .. tostring(value)
   end

   if #values > 0 then
      headers["Cookie"] = table.concat(values, "; ")
   end
end

local function list_contains(values, expected)
   if type(values) ~= "table" then
      return values == expected
   end

   for _, value in ipairs(values) do
      if value == expected then return true end
   end

   return false
end

local function count(map, key, n)
   key = tostring(key or "nil")
   map[key] = (map[key] or 0) + (n or 1)
end

local function bucket_index(sec)
   return sec % LATENCY_BUCKETS + 1
end

function scenario_runner.advance_latency_window(sec)
   local latency = scenario_runner.latency

   if latency.last_sec == nil then
      latency.last_sec = sec
      return
   end

   if sec <= latency.last_sec then
      return
   end

   if sec - latency.last_sec >= LATENCY_BUCKETS then
      latency.buckets = {}
      latency.total_cost = 0
      latency.total_count = 0
      latency.last_sec = sec
      return
   end

   for s = latency.last_sec + 1, sec do
      local idx = bucket_index(s)
      local bucket = latency.buckets[idx]

      if bucket then
         latency.total_cost = latency.total_cost - bucket.cost
         latency.total_count = latency.total_count - bucket.count
         bucket.sec = s
         bucket.cost = 0
         bucket.count = 0
      else
         latency.buckets[idx] = { sec = s, cost = 0, count = 0 }
      end
   end

   latency.last_sec = sec
end

function scenario_runner.record_latency(cost_ms)
   local sec = math.floor(now_ms() / 1000)
   scenario_runner.advance_latency_window(sec)

   local latency = scenario_runner.latency
   local idx = bucket_index(sec)
   local bucket = latency.buckets[idx]

   if not bucket then
      bucket = { sec = sec, cost = 0, count = 0 }
      latency.buckets[idx] = bucket
   end

   bucket.cost = bucket.cost + cost_ms
   bucket.count = bucket.count + 1
   latency.total_cost = latency.total_cost + cost_ms
   latency.total_count = latency.total_count + 1
end

function scenario_runner.avg_latency_ms()
   local sec = math.floor(now_ms() / 1000)
   scenario_runner.advance_latency_window(sec)

   local latency = scenario_runner.latency
   if latency.total_count <= 0 then
      return 0
   end

   return latency.total_cost / latency.total_count
end

function scenario_runner.empty_stat()
   return {
      requests = 0,
      responses = 0,
      status = {},
      body = {},
      expected_status = {},
      unexpected_status = {},
   }
end

function scenario_runner.empty_stats(config)
   local stats = {}
   for _, scenario in ipairs(config or scenario_runner.scenarios) do
      stats[scenario.name] = scenario_runner.empty_stat()
   end
   return stats
end

function scenario_runner.validate()
   local names = {}

   if type(scenario_runner.scenarios) ~= "table" or #scenario_runner.scenarios == 0 then
      error("no scenarios configured")
   end

   for i, scenario in ipairs(scenario_runner.scenarios) do
      if scenario.weight ~= nil then
         error(string.format("scenario %d uses unsupported field 'weight'", i))
      end
      if not scenario.name or scenario.name == "" then
         error(string.format("scenario %d missing required field 'name'", i))
      end
      if names[scenario.name] then
         error(string.format("duplicate scenario name '%s'", scenario.name))
      end
      names[scenario.name] = true
      if type(scenario.target_qps) ~= "number" or scenario.target_qps <= 0 then
         error(string.format("scenario '%s' requires positive numeric target_qps", scenario.name))
      end
   end
end

function scenario_runner.init(config, thread_id)
   local workers = tonumber(wrk.parallel_worker) or 1
   if workers < 1 then workers = 1 end

   scenario_runner.scenarios = config
   scenario_runner.by_name = {}
   scenario_runner.total_target_qps = 0
   scenario_runner.inflight = {}
   scenario_runner.reservations = {}
   scenario_runner.reservations_by_key = {}
   scenario_runner.latency = {
      buckets = {},
      total_cost = 0,
      total_count = 0,
      last_sec = nil,
   }
   scenario_runner.validate()

   local start = now_ms()
   local thread_phase = ((tonumber(thread_id) or 1) - 1) / workers
   for i, scenario in ipairs(scenario_runner.scenarios) do
      scenario_runner.by_name[scenario.name] = scenario
      scenario_runner.total_target_qps = scenario_runner.total_target_qps + scenario.target_qps
      scenario.thread_target_qps = scenario.target_qps / workers
      scenario.interval_ms = 1000.0 / scenario.thread_target_qps

      local scenario_phase = (i - 1) / #scenario_runner.scenarios
      local phase = (thread_phase + scenario_phase) % 1
      scenario.next_send_at = start + scenario.interval_ms * phase
   end

   scenario_runner.stats = scenario_runner.empty_stats()
   scenario_results = ""
end

function scenario_runner.reserve_next(key)
   local now = now_ms()
   local selected = nil

   for _, scenario in ipairs(scenario_runner.scenarios) do
      if not selected or scenario.next_send_at < selected.next_send_at then
         selected = scenario
      end
   end

   local slot_at = selected.next_send_at
   selected.next_send_at = selected.next_send_at + selected.interval_ms

   local delay_ms = slot_at - now
   if delay_ms < 0 then delay_ms = 0 end

   local reservation = {
      key = key,
      scenario = selected,
      ready_at = now + delay_ms,
      active = true,
   }

   scenario_runner.reservations[#scenario_runner.reservations + 1] = reservation

   if key ~= nil then
      scenario_runner.reservations_by_key[key] = reservation
   end

   return math.floor(delay_ms + 0.5)
end

function scenario_runner.pop_reservation(key)
   local now = now_ms()
   local best_index = nil
   local best_ready_at = nil

   if key ~= nil then
      local reservation = scenario_runner.reservations_by_key[key]
      if reservation and reservation.active then
         scenario_runner.reservations_by_key[key] = nil
         reservation.active = false
         return reservation.scenario
      end
   end

   for i, reservation in ipairs(scenario_runner.reservations) do
      if reservation.active ~= false and reservation.ready_at <= now and (not best_ready_at or reservation.ready_at < best_ready_at) then
         best_index = i
         best_ready_at = reservation.ready_at
      end
   end

   if not best_index then
      if #scenario_runner.reservations == 0 then
         scenario_runner.reserve_next(key)
      end
      best_index = 1
      while scenario_runner.reservations[best_index] and scenario_runner.reservations[best_index].active == false do
         table.remove(scenario_runner.reservations, best_index)
      end
   end

   local reservation = table.remove(scenario_runner.reservations, best_index)
   if reservation.key ~= nil and scenario_runner.reservations_by_key[reservation.key] == reservation then
      scenario_runner.reservations_by_key[reservation.key] = nil
   end
   reservation.active = false

   return reservation.scenario
end

function scenario_runner.build_request(scenario)
   local method = scenario.method or "GET"
   local path = append_params(scenario.path or "/", scenario.params)
   local headers = clone_headers(scenario.headers)

   append_cookies(headers, scenario.cookies)

   return wrk.format(method, path, headers, scenario.body)
end

function scenario_runner.classify_body(scenario, body)
   body = body or ""

   if type(scenario.body_classifier) == "function" then
      return scenario.body_classifier(body)
   end

   if type(scenario.body_match) == "table" then
      for name, pattern in pairs(scenario.body_match) do
         if body:find(pattern, 1, true) then
            return name
         end
      end
      return "unmatched"
   end

   if type(scenario.expect_body) == "string" then
      return body == scenario.expect_body and "expected" or "unexpected"
   end

   if body == "" then return "empty" end
   return "body"
end

function scenario_runner.record_response(scenario_name, status, body)
   local stat = scenario_runner.stats[scenario_name]
   local scenario = scenario_runner.by_name[scenario_name]
   if not stat or not scenario then return end

   stat.responses = stat.responses + 1
   count(stat.status, status)

   local bucket = scenario_runner.classify_body(scenario, body)
   count(stat.body, bucket)

   if scenario.expect_status then
      if list_contains(scenario.expect_status, status) then
         count(stat.expected_status, status)
      else
         count(stat.unexpected_status, status)
      end
   end
end

function scenario_runner.serialize_counts(lines, scenario_name, field, values)
   for key, value in pairs(values) do
      lines[#lines + 1] = table.concat({ scenario_name, field, tostring(key), tostring(value) }, "\t")
   end
end

function scenario_runner.serialize_stats(stats)
   local lines = {}

   for _, scenario in ipairs(scenario_runner.scenarios) do
      local stat = stats[scenario.name]
      lines[#lines + 1] = table.concat({ scenario.name, "requests", "_", tostring(stat.requests) }, "\t")
      lines[#lines + 1] = table.concat({ scenario.name, "responses", "_", tostring(stat.responses) }, "\t")
      scenario_runner.serialize_counts(lines, scenario.name, "status", stat.status)
      scenario_runner.serialize_counts(lines, scenario.name, "body", stat.body)
      scenario_runner.serialize_counts(lines, scenario.name, "expected_status", stat.expected_status)
      scenario_runner.serialize_counts(lines, scenario.name, "unexpected_status", stat.unexpected_status)
   end

   return table.concat(lines, "\n")
end

function scenario_runner.publish_stats()
   scenario_results = scenario_runner.serialize_stats(scenario_runner.stats)
end

function scenario_runner.merge_serialized_stats(dst, text)
   if type(text) ~= "string" or text == "" then return end

   for line in text:gmatch("[^\n]+") do
      local name, field, key, value = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
      value = tonumber(value) or 0

      local stat = dst[name]
      if stat then
         if field == "requests" then
            stat.requests = stat.requests + value
         elseif field == "responses" then
            stat.responses = stat.responses + value
         elseif field == "status" then
            count(stat.status, key, value)
         elseif field == "body" then
            count(stat.body, key, value)
         elseif field == "expected_status" then
            count(stat.expected_status, key, value)
         elseif field == "unexpected_status" then
            count(stat.unexpected_status, key, value)
         end
      end
   end
end

function scenario_runner.aggregate_thread_stats()
   local aggregate = scenario_runner.empty_stats(scenarios)

   if #scenario_runner.threads == 0 then
      scenario_runner.merge_serialized_stats(aggregate, scenario_runner.serialize_stats(scenario_runner.stats))
      return aggregate
   end

   for _, thread in ipairs(scenario_runner.threads) do
      scenario_runner.merge_serialized_stats(aggregate, thread:get("scenario_results"))
   end

   return aggregate
end

function scenario_runner.print_distribution(title, values, total, indent)
   indent = indent or "    "
   print(indent .. title .. ":")

   if not values or next(values) == nil then
      print(indent .. "  <none>")
      return
   end

   for key, value in pairs(values) do
      local pct = total > 0 and value * 100.0 / total or 0
      print(string.format("%s  %s: %d (%.2f%%)", indent, tostring(key), value, pct))
   end
end

function scenario_runner.report(stats, summary)
   if scenario_runner.total_target_qps == 0 then
      scenario_runner.scenarios = scenarios
      scenario_runner.stats = scenario_runner.empty_stats(scenarios)
      for _, scenario in ipairs(scenario_runner.scenarios) do
         scenario_runner.total_target_qps = scenario_runner.total_target_qps + scenario.target_qps
      end
   end

   local duration_s = summary and summary.duration and summary.duration / 1000000.0 or 0
   local total_requests = 0
   for _, stat in pairs(stats) do
      total_requests = total_requests + stat.requests
   end

   print("================ Scenario Report ================")
   print(string.format("total scenario requests: %d", total_requests))
   print(string.format("total target_qps: %s", tostring(scenario_runner.total_target_qps)))

   for _, scenario in ipairs(scenario_runner.scenarios) do
      local stat = stats[scenario.name] or scenario_runner.empty_stat()
      local request_pct = total_requests > 0 and stat.requests * 100.0 / total_requests or 0
      local actual_qps = duration_s > 0 and stat.requests / duration_s or 0

      print(string.format("\n[%s]", scenario.name))
      print(string.format("  target_qps: %s", tostring(scenario.target_qps)))
      print(string.format("  actual_qps: %.2f", actual_qps))
      print(string.format("  requests: %d (actual ratio %.2f%%)", stat.requests, request_pct))
      print(string.format("  responses: %d", stat.responses))
      scenario_runner.print_distribution("status", stat.status, stat.responses, "  ")
      scenario_runner.print_distribution("body", stat.body, stat.responses, "  ")

      if scenario.expect_status then
         scenario_runner.print_distribution("expected_status", stat.expected_status, stat.responses, "  ")
         scenario_runner.print_distribution("unexpected_status", stat.unexpected_status, stat.responses, "  ")
      end
   end
end

local setup_counter = 0

setup = function(thread, connections)
   setup_counter = setup_counter + 1
   thread:set("id", setup_counter)
   thread:set("connections", connections)
   scenario_runner.threads[#scenario_runner.threads + 1] = thread
end

init = function(args)
   scenario_runner.init(scenarios, id)
end

delay = function(key)
   return scenario_runner.reserve_next(key)
end

request = function(key)
   local scenario = scenario_runner.pop_reservation(key)
   local stat = scenario_runner.stats[scenario.name]
   local start_ms = now_ms()
   local queue = scenario_runner.inflight[key]

   if not queue then
      queue = {}
      scenario_runner.inflight[key] = queue
   end

   stat.requests = stat.requests + 1
   queue[#queue + 1] = {
      scenario = scenario.name,
      start_ms = start_ms,
   }
   scenario_runner.publish_stats()

   return scenario_runner.build_request(scenario)
end

response = function(status, headers, body, key)
   local queue = scenario_runner.inflight[key]
   local item = queue and table.remove(queue, 1)
   if item then
      scenario_runner.record_latency(now_ms() - item.start_ms)
      scenario_runner.record_response(item.scenario, status, body)
      scenario_runner.publish_stats()
   end
end

reset = function(key)
   local reservation = scenario_runner.reservations_by_key[key]
   if reservation then
      reservation.active = false
      scenario_runner.reservations_by_key[key] = nil
   end

   scenario_runner.inflight[key] = nil
end

done = function(summary, latency, requests)
   scenario_runner.report(scenario_runner.aggregate_thread_stats(), summary)
end
