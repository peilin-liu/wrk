## 1. Command-Line Configuration

- [ ] 1.1 Add `rtimeout` field to the runtime configuration structure.
- [ ] 1.2 Add `--rtimeout <T>` to long options and short option parsing as needed.
- [ ] 1.3 Parse `--rtimeout <T>` with the existing time argument parser and store it in milliseconds.
- [ ] 1.4 Update usage text to document `--rtimeout <T>` separately from `--timeout <T>`.
- [ ] 1.5 Decide and implement default behavior for omitted `--rtimeout` without changing existing `--timeout` semantics.

## 2. Connection State

- [ ] 2.1 Add per-connection state for read-idle tracking, including last read activity time or deadline timestamp.
- [ ] 2.2 Add state needed to ignore stale timeout callbacks after reconnects or completed responses.
- [ ] 2.3 Initialize read-idle state when a connection is created or reconnected.

## 3. Event-Loop Timeout Enforcement

- [ ] 3.1 Start or refresh read-idle monitoring when a request is written and becomes in flight.
- [ ] 3.2 Refresh read-idle activity only when actual response bytes are read from the socket.
- [ ] 3.3 Detect expiry when no response bytes arrive within `--rtimeout` while a request is in flight.
- [ ] 3.4 On read-idle expiry, increment `errors.timeout` and reconnect or recycle the affected connection.
- [ ] 3.5 Ensure read-idle expiry is not counted as `errors.read`.
- [ ] 3.6 Avoid relying on `SO_RCVTIMEO`; remove or bypass the previous socket receive timeout attempt.

## 4. Validation

- [ ] 4.1 Build the project and fix compile warnings or errors.
- [ ] 4.2 Verify `wrk --help` shows both `--timeout` and `--rtimeout` with distinct meanings.
- [ ] 4.3 Test a server that accepts a request but sends no response data; confirm `--rtimeout` records timeout errors and recycles connections.
- [ ] 4.4 Test a slow streaming response that sends chunks within `--rtimeout`; confirm the connection stays active.
- [ ] 4.5 Test existing `--timeout` behavior remains based on completed request latency.
