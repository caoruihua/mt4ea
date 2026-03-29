## ADDED Requirements

### Requirement: The spike momentum strategy SHALL detect sudden one-way impulses in a rolling five-minute window
The system SHALL provide a dedicated spike momentum strategy that evaluates market data on every tick using a rolling five-minute window instead of waiting for candle close.

#### Scenario: Buy-side impulse candidate is detected intrabar
- **WHEN** the last 300 seconds contain an upward price expansion of at least 40 USD from the window low to the window high
- **AND** the current price remains near the window high
- **THEN** the strategy SHALL treat the move as a buy-side impulse candidate without waiting for the current M5 candle to close

#### Scenario: Sell-side impulse candidate is detected intrabar
- **WHEN** the last 300 seconds contain a downward price expansion of at least 40 USD from the window high to the window low
- **AND** the current price remains near the window low
- **THEN** the strategy SHALL treat the move as a sell-side impulse candidate without waiting for the current M5 candle to close

### Requirement: The spike momentum strategy SHALL use pullback ratio filtering instead of trend filtering
The system SHALL evaluate impulse quality using a pullback-ratio rule and SHALL NOT require a trend-direction filter before entry.

#### Scenario: Buy signal is blocked by excessive pullback
- **WHEN** a buy-side impulse candidate exists
- **AND** `(windowHigh - currentPrice) / (windowHigh - windowLow)` exceeds the configured maximum pullback ratio
- **THEN** the strategy SHALL reject the buy entry

#### Scenario: Sell signal is blocked by excessive pullback
- **WHEN** a sell-side impulse candidate exists
- **AND** `(currentPrice - windowLow) / (windowHigh - windowLow)` exceeds the configured maximum pullback ratio
- **THEN** the strategy SHALL reject the sell entry

#### Scenario: Default pullback ratio allows clean impulse continuation
- **WHEN** an impulse candidate exists
- **AND** the pullback ratio is less than or equal to the default maximum of 20%
- **THEN** the strategy SHALL allow the corresponding entry signal

### Requirement: The spike momentum strategy SHALL enter immediately with fixed risk parameters
The system SHALL submit the spike momentum entry as soon as the intrabar impulse and pullback conditions are satisfied, with fixed stop-loss and take-profit distances.

#### Scenario: Buy signal uses fixed stop-loss and take-profit
- **WHEN** a valid buy-side spike momentum signal is generated
- **THEN** the strategy SHALL request a buy order with a fixed stop-loss price distance of 20 USD and a fixed take-profit price distance of 35 USD

#### Scenario: Sell signal uses fixed stop-loss and take-profit
- **WHEN** a valid sell-side spike momentum signal is generated
- **THEN** the strategy SHALL request a sell order with a fixed stop-loss price distance of 20 USD and a fixed take-profit price distance of 35 USD

### Requirement: The spike momentum strategy SHALL avoid repeated entries during the same impulse
The system SHALL prevent duplicate entries from the same directional spike event until that impulse window is no longer active.

#### Scenario: Repeated buy triggers are suppressed within one spike event
- **WHEN** a buy-side spike has already produced an entry
- **AND** the same spike event is still considered active
- **THEN** the strategy SHALL NOT generate another buy entry from that event

#### Scenario: Repeated sell triggers are suppressed within one spike event
- **WHEN** a sell-side spike has already produced an entry
- **AND** the same spike event is still considered active
- **THEN** the strategy SHALL NOT generate another sell entry from that event

### Requirement: The spike momentum strategy SHALL emit complete decision logs
The system SHALL log the full decision chain for the spike momentum strategy so operators can distinguish threshold misses, pullback filtering, duplicate-trigger suppression, position blocking, and execution outcomes.

#### Scenario: Candidate detection is logged
- **WHEN** the strategy evaluates a rolling five-minute window
- **THEN** it SHALL log the window high, window low, current price, impulse direction, and impulse size used for the decision

#### Scenario: Filter rejection is logged
- **WHEN** a spike candidate is rejected
- **THEN** the strategy SHALL log the specific rejection reason, including pullback ratio or duplicate-trigger suppression when applicable

#### Scenario: Signal and execution outcome are logged
- **WHEN** the strategy generates a valid entry request
- **THEN** the system SHALL log the signal direction, configured stop-loss, configured take-profit, and the final execution outcome
