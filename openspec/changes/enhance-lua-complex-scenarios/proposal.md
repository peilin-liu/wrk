## Why

我们需要测试一个多规则限流服务。限流规则由 path、header、query parameter、cookie 等条件组合而成，每条规则都需要单独构造访问流量，用来触发或不触发对应限流规则。测试结束后，需要按请求场景统计实际响应码和响应体分布，并判断这些结果是否符合预期。

## What Changes

- 新增一个独立 Lua 脚本，用于定义多条命名请求场景/规则。
- 在 C 层为 Lua 暴露 `wrk.now()`，返回当前毫秒时间，供 Lua 脚本做时间窗口调度。
- 每个请求场景支持配置 path、headers、query parameters、cookies、method、body 和 `target_qps`。
- 使用每个场景的 `target_qps` 做 Lua 侧 QPS 调度；不支持单独的 `weight` 配置。
- 每个场景支持配置预期响应码，以及预期响应体、响应体匹配规则或 Lua classifier 函数。
- 在 Lua 中记录每次生成请求所属的场景，使响应可以归因到对应场景。
- 测试结束时按场景聚合响应结果。
- 输出每个场景下的响应码分布、响应体分类分布，以及各类结果的比例。
- 支持一次运行中测试至少六条限流规则，包括 path、header、parameter、cookie 的组合匹配规则。

## Capabilities

### New Capabilities
- `lua-complex-scenarios`: 提供 Lua-only 的多场景请求生成和按场景响应聚合能力，用于复杂限流规则测试。

### Modified Capabilities

## Impact

- 影响代码：新增 Lua 脚本文件，并在 `src/script.c` 中增加最小 C 层绑定 `wrk.now()`；不修改 wrk 事件循环和请求发送模型。
- 用户接口：新增 Lua 场景定义方式，包含请求字段、`target_qps`、预期响应码、响应体匹配或分类函数。
- 运行行为：通过 wrk 现有 Lua 回调完成场景选择、请求/响应关联和最终统计输出。
- 依赖：不引入新的外部依赖。
