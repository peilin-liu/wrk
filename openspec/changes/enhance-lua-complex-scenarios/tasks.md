## 1. Lua 脚本结构

- [x] 1.1 新建独立 Lua 脚本文件用于复杂限流场景测试。
- [x] 1.2 在脚本中定义本地 `scenario_runner` 或等价命名空间，避免污染全局变量。
- [x] 1.3 增加 C 层 `wrk.now()` Lua 绑定，仅用于提供毫秒级当前时间。

## 2. Scenario 配置

- [x] 2.1 定义 scenario 配置结构，支持 `name`、`target_qps`、`method`、`path`、`headers`、`params`、`cookies`、`body`。
- [x] 2.2 提供至少六条示例限流 scenario，覆盖 path、header、parameter、cookie 的组合规则。
- [x] 2.3 实现 query parameter 拼接逻辑。
- [x] 2.4 实现 cookie header 构造逻辑。
- [x] 2.5 实现 scenario 配置校验，要求 `name` 和 `target_qps` 必填。
- [x] 2.6 明确不支持 `weight` 配置。

## 3. 请求生成与场景选择

- [x] 3.1 基于各 scenario 的 `target_qps` 比例构建确定性选择逻辑。
- [x] 3.2 在 `request(key)` 中选择 scenario 并生成对应 HTTP 请求。
- [x] 3.3 使用 `wrk.format()` 构造最终请求。
- [x] 3.4 使用 `delay()` 做 Lua 侧 QPS 调度。
- [x] 3.5 记录每次生成请求所属 scenario，用于后续响应归因。

## 4. 响应统计与分类

- [x] 4.1 在 `response(status, headers, body)` 中将响应归因到对应 scenario。
- [x] 4.2 为每个 scenario 统计请求数和响应数。
- [x] 4.3 为每个 scenario 统计响应码分布。
- [x] 4.4 支持每个 scenario 配置预期响应码。
- [x] 4.5 支持每个 scenario 配置响应体匹配值或 Lua body classifier 函数。
- [x] 4.6 使用 body classifier 或匹配结果统计响应体分类分布。

## 5. 最终报告

- [x] 5.1 在 `done(summary, latency, requests)` 中汇总各线程统计结果。
- [x] 5.2 输出每个 scenario 的请求数、响应数和实际请求比例。
- [x] 5.3 输出每个 scenario 的响应码计数和百分比。
- [x] 5.4 输出每个 scenario 的响应体分类计数和百分比。
- [x] 5.5 在报告中展示实际分布和 `target_qps` 比例的差异，方便判断流量是否符合预期。

## 6. 验证

- [x] 6.1 使用 Lua 语法检查或试运行确认脚本无语法错误。
- [x] 6.2 使用 mock 或测试服务验证六条 scenario 都能生成请求。
- [x] 6.3 验证 `target_qps` 用于 Lua 侧 QPS 调度。
- [x] 6.4 验证响应码分布和响应体分类分布输出正确。
- [x] 6.5 验证没有 C 源码文件被本变更修改。
