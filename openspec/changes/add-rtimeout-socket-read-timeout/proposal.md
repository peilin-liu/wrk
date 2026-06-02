## Why

The existing `--timeout` only classifies completed requests whose total latency exceeds the configured threshold; it does not bound how long an established connection may sit waiting for response bytes. Users need a separate read-idle timeout so a connection that receives no data for too long is failed and recycled instead of remaining stuck until the server eventually responds or closes.

## What Changes

- Add a new `--rtimeout <T>` command-line option for the maximum allowed socket read-idle interval.
- Keep existing `--timeout <T>` semantics for whole-request latency accounting and timeout error classification.
- Track the last successful read activity per connection and treat connections with no readable data for longer than `--rtimeout` as timed out.
- On read-idle timeout, increment timeout errors and reconnect/recycle the affected connection.
- Document option behavior in CLI usage text.
- Avoid relying on `SO_RCVTIMEO` for this behavior because wrk uses non-blocking sockets and event-loop based IO.

## Capabilities

### New Capabilities
- `socket-read-idle-timeout`: Adds a user-configurable read-idle timeout for non-blocking socket connections.

### Modified Capabilities

## Impact

- Affected code: command-line parsing in `src/wrk.c`, connection state in `src/wrk.h`, event-loop/timer handling around socket reads, timeout/error accounting, and usage output.
- User-facing API: adds `--rtimeout <T>` without changing existing `--timeout <T>` behavior.
- Dependencies: no new external dependencies expected.
