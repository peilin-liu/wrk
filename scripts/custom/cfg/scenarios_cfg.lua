return {
   {
      name = "limited_by_header",
      enable = true,
      target_qps = 13,
      method = "GET",
      path = "/add",
      headers = {
         ["LimitHeader"] = "B",
      },
      params = {
         a = "3",
         b = "4",
      },
      expect_status = { 439 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by header", 1, true) then return "limit_by_header" end
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_cookie",
      enable = true,
      target_qps = 13,
      method = "GET",
      path = "/add",
      params = {
         a = "4",
         b = "5",
      },
      cookies = {
         uid = "tester",
         token = "cast",
         a = "a",
      },
      expect_status = { 449 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by cookie", 1, true) then return "limit_by_cookie" end
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_parameter",
      enable = true,
      target_qps = 13,
      method = "GET",
      path = "/add",
      headers = {
         ["LimitHeader"] = "C",
      },
      params = {
         a = "3",
         b = "11",
      },
      expect_status = { 459 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by parameter", 1, true) then return "limit_by_parameter" end
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_total",
      enable = true,
      target_qps = 100,
      method = "GET",
      path = "/add",
      params = {
         a = "11",
         b = "12",
      },
      expect_status = { 200 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by request total", 1, true) then return "limit_by_request_total" end
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_ip_total",
      enable = true,
      target_qps = 35,
      method = "GET",
      path = "/favicon.ico",
      params = {
      },
      expect_status = { 479 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_ip_path",
      enable = true,
      target_qps = 13,
      method = "GET",
      path = "/static/css/base.css",
      headers = {
         ["LimitHeader"] = "NoLimit",
      },
      params = {
      },
      expect_status = { 489 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by ip and path", 1, true) then return "limit_by_ip_path" end
         if body:find("limit by ip total", 1, true) then return "limit_by_ip_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
   {
      name = "limited_by_total ver",
      enable = true,
      target_qps = 3000,
      method = "GET",
      path = "/version",
      expect_status = { 200 },
      body_classifier = function(body)
         body = body or ""
         if body:find("limit by request total", 1, true) then return "limit_by_request_total" end
         if body == "" then return "empty" end
         return "other"
      end,
   },
}
