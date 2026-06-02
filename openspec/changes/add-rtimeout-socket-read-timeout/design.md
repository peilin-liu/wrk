## Context

`wrk` uses non-blocking sockets and an event loop for connection IO. The existing `--timeout` value is used as a request latency threshold: a request is counted as a timeout only after a full response is received and its elapsed time exceeds the configured bound. This does not protect a connection that has written a request and then receives no response bytes for a long period.

The recent attempt to set `SO_RCVTIMEO` does not solve the problem reliably because non-blocking `recv` calls do not wait for data; they return immediately with `EAGAIN` when no data is available. Read-idle timeout behavior therefore needs to live in the event-loop layer, not in blocking socket options.

## Goals / Non-Goals

**Goals:**

- Add `--rtimeout <T>` to configure the maximum interval a connection may wait without receiving response data.
- Preserve current `--timeout <T>` request latency accounting behavior.
- Detect read-idle timeouts while a request/response is in flight and recycle the affected connection.
- Count read-idle expirations as timeout errors, not generic read errors.
- Support the same time argument format used by other wrk time options.

**Non-Goals:**

- Do not change the meaning of `--timeout`.
- Do not rely on `SO_RCVTIMEO` for non-blocking sockets.
- Do not add new external dependencies.
- Do not implement per-request application-level deadlines for pipelined sub-requests beyond the connection-level read-idle behavior.

## Decisions

### Use a separate option instead of changing `--timeout`

Add `--rtimeout <T>` rather than reusing `--timeout` for read-idle behavior.

Rationale: `--timeout` already has observable behavior in latency statistics and timeout classification after response completion. Changing it to actively close idle connections could alter existing benchmark results and break user expectations.

Alternative considered: make `--timeout` both the latency threshold and read-idle timeout. Rejected because it couples two different concepts: full request duration and no-data read idle duration.

### Implement timeout in the event loop

Track read activity on each connection and use event-loop time events to detect idle connections. When a connection starts a request, initialize its read deadline. Each successful read of response bytes refreshes the deadline. If the timer observes that the connection still has an in-flight request and no data has arrived within `--rtimeout`, increment `errors.timeout` and reconnect the socket.

Rationale: wrk sockets are non-blocking, so event-loop timers are the correct place to model elapsed idle time.

Alternative considered: keep `SO_RCVTIMEO`. Rejected because it only limits blocking `recv` wait time and does not control event-loop waiting.

### Treat timeout as connection-level read idle

Apply `--rtimeout` per connection, based on the last successful read activity while a request is pending.

Rationale: wrk multiplexes work by connection and may use HTTP pipelining. A connection-level read-idle timeout is simple, predictable, and matches the symptom: no response bytes are arriving on this socket.

Alternative considered: maintain individual timers for every pipelined request. Rejected for this change because it adds complexity and does not map cleanly to byte-level HTTP parser progress in the current code.

### Default behavior

Default `--rtimeout` should preserve current behavior unless the user opts in, or it should use an explicit conservative default only if required for compatibility with existing timeout constants.

Rationale: adding a new option should not unexpectedly fail connections in existing benchmark runs.

Open implementation choice: use `0` as disabled by default, or default it to the existing socket/request timeout constant. This should be decided during implementation based on compatibility goals.

## Risks / Trade-offs

- Timer overhead with many connections → Use per-connection timers only while requests are in flight, or use a periodic sweep per thread if event-loop timer count becomes costly.
- Race between timer firing and response completion → Check connection state and deadline timestamp before counting timeout; ignore stale timer events.
- HTTP pipelining ambiguity → Define `--rtimeout` as connection read-idle timeout, not per-pipelined-request timeout.
- TLS reads may return retry states without bytes → Refresh deadline only when actual bytes are received, not when `SSL_read` asks to retry.
- Behavior change if enabled by default → Prefer opt-in default or document the default clearly in usage output.
