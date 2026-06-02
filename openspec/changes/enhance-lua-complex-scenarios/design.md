## Context

当前 Lua 接口已经可以通过 `request(key)` 生成动态请求，也可以通过 `response(status, headers, body)` 查看响应结果。但它没有内置机制来描述多条命名测试场景，也没有机制把某个响应关联回生成该请求的场景，更没有在测试结束后按场景聚合响应分布。

这次目标场景是多规则限流验证。一次压测需要同时覆盖多条限流规则，这些规则由 path、header、query parameter、cookie 等条件组合而成。每条规则都需要独立的请求形态、目标 QPS、预期响应码和预期响应体，最终输出要能看出每条规则的实际表现是否符合预期。

## Goals / Non-Goals

**Goals:**

- 新建一个 Lua 脚本，在 Lua 层提供 scenario 抽象，用于定义多条命名请求规则。
- 每个 scenario 支持配置 path、headers、query parameters、cookies、method、body 和 `target_qps`。
- 允许最小 C 层改动：新增 `wrk.now()` 给 Lua 使用；除此之外不修改 wrk 事件循环和请求发送模型。
- 通过 `target_qps` 表达各 scenario 的目标流量比例，不新增逻辑特意控制全局总 QPS。
- 尽量保持现有 `request`、`response`、`done` 回调兼容。
- 能把每个生成的请求和对应 scenario 关联起来，让响应结果可以按 scenario 归类统计。
- 测试结束时输出每个 scenario 下的响应码分布和响应体分类分布。
- 支持一次运行中至少覆盖六条限流规则。

**Non-Goals:**

- 不实现限流服务本身。
- 不引入新的外部依赖。
- 不修改 wrk 事件循环和请求发送模型；C 层只新增 `wrk.now()` 时间函数绑定。
- 不扩展除 `wrk.now()` 之外的 wrk C 层 Lua API。
- 不要求用户重写已有的简单 wrk Lua 脚本。
- 不保证每个 scenario 的全局 QPS 绝对精确；`target_qps` 只用于场景间请求选择比例，不用于主动控制总 QPS。
- 不支持 `weight` 作为单独配置项。
- 不在 C 层解析任意响应体结构；响应体分类逻辑保留在 Lua 中配置。

## Decisions

### 只通过新增 Lua 脚本实现 scenario 编排

本变更只新增一个 Lua 脚本或 Lua 示例模块，不修改 C 代码。

原因：请求构造、预期结果、响应体分类都和具体业务强相关，用 Lua 表达更灵活。把编排逻辑留在 Lua 中，可以减少 C 代码改动，降低影响 wrk 稳定性的风险。

考虑过的替代方案：在 C 层实现 scenario 定义和聚合统计。暂不采用，因为这会增加 native 状态管理复杂度，也会降低用户自定义场景的灵活性。

### 通过 `wrk.now()` 提供毫秒时间

在 C 层为 Lua 暴露 `wrk.now()`，返回当前 wall-clock 毫秒时间。Lua 脚本使用它做 QPS 时间窗口、delay 计算和请求耗时统计。

原因：Lua 标准 `os.time()` 只有秒级精度，`os.clock()` 通常表示 CPU 时间，都不适合 100ms 级别的 QPS 调度。把时间函数放在 wrk API 中，比在 Lua 中使用 LuaJIT FFI 更直接，也更符合脚本使用方式。

考虑过的替代方案：在 Lua 中通过 FFI 调用 `gettimeofday()`。暂不采用，因为这会让脚本依赖 LuaJIT FFI 细节；`wrk.now()` 更清晰。

### 使用 target_qps 作为场景 QPS 配置

每个 scenario 使用 `target_qps` 描述目标请求速率。脚本使用 `delay()` 进行 Lua 侧 QPS 调度：按线程数切分每个 scenario 的目标 QPS，基于时间窗口计算下一次请求延迟，并用线程最近 10 秒平均请求耗时修正 delay。实际总 QPS 仍受连接数、响应耗时和服务端能力限制。

原因：限流测试关心的是每条规则是否达到指定请求速率，以及某条规则是否在该速率下被触发。Lua 侧窗口调度可以在不改 wrk 事件循环的前提下实现较精确的闭环 QPS 控制。

考虑过的替代方案：只把 `target_qps` 当作场景选择比例，不主动控制总 QPS。暂不采用，因为当前需求需要更精确的 QPS 控制。

考虑过的替代方案：同时支持 `weight` 和 `target_qps`。暂不采用，因为会增加配置歧义；本变更只支持 `target_qps`。

### 使用 request key 和线程内计数做确定性场景选择

复用当前 `request(key)` 中传入的 key，结合每个线程自己的请求计数，在 Lua 脚本中按 `target_qps` 比例选择 scenario。

原因：当前分支已经把连接位置 key 传给 Lua，请求选择逻辑可以直接在 Lua 中利用这个信息。对多条限流规则测试来说，基于 `target_qps` 的确定性选择已经足够。

考虑过的替代方案：新增 C 层请求调度器。暂不采用，因为本变更明确不修改 C 代码。

### 在 Lua 中管理 request/response 关联

当某个 scenario 生成请求时，Lua 把选中的 scenario 记录到当前线程的 FIFO 队列中。`response(status, headers, body)` 回调触发时，从队列中取出对应 scenario id，然后把响应结果累计到该 scenario 下。

原因：wrk 在同一个连接上按 HTTP 请求顺序处理响应，常规非 pipeline 场景下，Lua 侧 FIFO 可以满足 request/response 归因需求。这样可以避免在 C 的 connection/request 状态中新增 scenario id 字段。

考虑过的替代方案：扩展 C 层，让 `response` 回调直接带上请求元数据。暂不采用，因为本变更不修改 C 代码；如果后续 pipeline 或并发归因出现问题，需要作为单独变更评估。

### 响应体分类保持可配置

每个 scenario 可以定义预期响应体，也可以定义 Lua classifier 函数。聚合时不一定直接使用完整 body 作为维度，而是可以使用“命中的预期名称”“自定义分类结果”“原始 body 摘要”等 bucket。

原因：限流响应体在不同产品或部署中可能不同，有些 body 还可能包含动态字段。Lua classifier 能让用户自己决定如何归类，避免 C 层引入复杂 parser。

考虑过的替代方案：只按原始 body 字符串聚合。暂不采用，因为原始 body 可能很大或包含动态字段，会导致输出噪声太多。

### 以示例脚本/可复用 Lua 模块作为主要用户接口

交付一个可复用 Lua 示例或模块，展示如何定义六条限流规则、如何生成请求、如何记录响应、如何在 `done` 阶段输出聚合结果。

原因：这个能力更像测试工作流增强。清晰的 Lua 使用方式能快速产生价值，同时不改变 wrk 的基础运行模型。

## Risks / Trade-offs

- Pipeline 下 request/response 归因可能不准确 → 初版示例优先面向非 pipeline 或响应顺序可保证的场景，并明确说明归因假设是同一线程/连接内响应按请求顺序返回。
- 每个 scenario 的实际 QPS 可能和 `target_qps` 有偏差 → 使用 `delay()` 做闭环窗口调度，并在最终报告中输出 target/actual QPS，方便用户校验偏差。
- 多线程 Lua 状态不共享 → 每个线程独立按 `target_qps` 比例调度，最终通过 `done` 汇总各线程结果。
- 响应体维度可能过多 → 默认推荐使用 body classifier 或预期 bucket，而不是直接按完整原始 body 聚合。
- scenario 数量较多时输出可能太长 → 输出每个 scenario 的摘要，以及主要 status/body bucket。
- 可能和已有脚本的全局变量冲突 → 辅助函数放到命名空间下，例如 `scenario_runner`，并尽量使用 local 变量。
