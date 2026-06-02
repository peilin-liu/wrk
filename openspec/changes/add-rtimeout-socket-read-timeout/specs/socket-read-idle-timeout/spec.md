## ADDED Requirements

### Requirement: Read-idle timeout option
The system SHALL provide a `--rtimeout <T>` command-line option that configures the maximum time an established connection may wait without receiving response bytes while a request is in flight.

#### Scenario: User configures read-idle timeout
- **WHEN** the user starts `wrk` with `--rtimeout 2s`
- **THEN** the system uses 2 seconds as the maximum no-data read interval for each active connection

#### Scenario: User omits read-idle timeout
- **WHEN** the user starts `wrk` without `--rtimeout`
- **THEN** the system preserves existing `--timeout` request latency behavior and does not reinterpret `--timeout` as the read-idle timeout

### Requirement: Read-idle timeout detection
The system SHALL detect when a connection with an in-flight request receives no response bytes for longer than the configured `--rtimeout` interval.

#### Scenario: Connection receives no response data
- **WHEN** a connection has written a request and no response bytes are received for longer than `--rtimeout`
- **THEN** the system records a timeout error for that connection and reconnects or recycles the connection

#### Scenario: Connection receives response data before timeout
- **WHEN** a connection receives response bytes before the configured `--rtimeout` interval expires
- **THEN** the system treats the connection as active and does not record a read-idle timeout for that interval

### Requirement: Read activity refreshes the timeout
The system SHALL refresh the read-idle timeout whenever actual response bytes are successfully read from the socket.

#### Scenario: Slow streaming response remains active
- **WHEN** a response arrives in multiple chunks and each chunk is received within `--rtimeout` of the previous chunk
- **THEN** the system keeps the connection open and continues processing the response

#### Scenario: Retry without bytes does not refresh timeout
- **WHEN** a non-blocking read or TLS read retry occurs without receiving bytes
- **THEN** the system does not refresh the read-idle timeout

### Requirement: Timeout accounting
The system SHALL count read-idle timeout expirations as timeout errors rather than read errors.

#### Scenario: Read-idle timeout expires
- **WHEN** a connection exceeds the configured read-idle timeout
- **THEN** the reported socket error counters include the event in the timeout count

### Requirement: Non-blocking IO compatible implementation
The system MUST implement read-idle timeout behavior independently of blocking socket receive timeouts such as `SO_RCVTIMEO`.

#### Scenario: Non-blocking socket has no readable data
- **WHEN** a non-blocking socket has no readable data available
- **THEN** the system relies on event-loop timing to enforce `--rtimeout` rather than waiting inside `recv`
