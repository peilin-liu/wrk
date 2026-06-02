return {
   {
      name = "limited_by_header",
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
         return body:find("limit") and "limited" or "other"
      end,
   },
   {
      name = "limited_by_cookie",
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
      },
      expect_status = { 449 },
      body_classifier = function(body)
         return body == '{"error": "limit by cookie", "code": 500}'
      end,
   },
   {
      name = "limited_by_parameter",
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
         return body == '{"error": "limit by parameter", "code": 500}'
      end,
   },
   {
      name = "limited_by_total",
      target_qps = 10,
      method = "GET",
      path = "/add",
      params = {
         a = "11",
         b = "12",
      },
      expect_status = { 200 },
      body_classifier = function(body)
         return body == '{"error": "limit by request total", "code": 500}'
      end,
   },
   {
      name = "limited_by_ip_total",
      target_qps = 35,
      method = "GET",
      path = "/favicon.ico",
      params = {
      },
      expect_status = { 479 },
      body_classifier = function(body)
         return body == '{"error": "limit by ip total", "code": 500}'
      end,
   },
   {
      name = "limited_by_ip_path",
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
         return body == '{"error": "limit by ip and path 1", "code": 500}'
      end,
   },
}
