return {
   {
      name = "path-rule-trigger",
      target_qps = 100,
      method = "GET",
      path = "/rate/path",
      expect_status = { 429 },
      body_classifier = function(body)
         return body:find("limit") and "limited" or "other"
      end,
   },
   {
      name = "path-rule-pass",
      target_qps = 20,
      method = "GET",
      path = "/rate/path-pass",
      expect_status = { 200 },
      body_classifier = function(body)
         return body == "" and "empty" or "body"
      end,
   },
   {
      name = "header-rule-trigger",
      target_qps = 80,
      method = "GET",
      path = "/rate/header",
      headers = {
         ["X-Limit-Key"] = "header-hot",
      },
      expect_status = { 429 },
      body_match = {
         limited = "too many requests",
      },
   },
   {
      name = "parameter-rule-trigger",
      target_qps = 60,
      method = "GET",
      path = "/rate/parameter",
      params = {
         user = "param-hot",
         bucket = "p1",
      },
      expect_status = { 429 },
      body_match = {
         limited = "too many requests",
      },
   },
   {
      name = "cookie-rule-trigger",
      target_qps = 40,
      method = "GET",
      path = "/rate/cookie",
      cookies = {
         uid = "cookie-hot",
         group = "g1",
      },
      expect_status = { 429 },
      body_match = {
         limited = "too many requests",
      },
   },
   {
      name = "combined-rule-trigger",
      target_qps = 30,
      method = "POST",
      path = "/rate/combined",
      headers = {
         ["X-Limit-Key"] = "combined-hot",
         ["Content-Type"] = "application/json",
      },
      params = {
         region = "cn",
         action = "create",
      },
      cookies = {
         uid = "combined-user",
      },
      body = '{"hello":"world"}',
      expect_status = { 429 },
      body_classifier = function(body)
         return body:find("limit") and "limited" or "other"
      end,
   },
}
