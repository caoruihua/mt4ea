## MODIFIED Requirements

### Requirement: The system SHALL evaluate registered strategies and choose the highest-priority valid signal
The strategy registry SHALL support strategies that evaluate intrabar rolling windows and SHALL allow the spike momentum strategy to compete in the centralized signal-selection flow.

#### Scenario: Intrabar rolling-window strategy is evaluated on each tick
- **WHEN** the registry processes a new tick
- **THEN** it SHALL permit the spike momentum strategy to evaluate the latest rolling five-minute window without requiring candle-close confirmation

#### Scenario: Spike momentum strategy participates in centralized selection
- **WHEN** the spike momentum strategy produces a valid signal on the current tick
- **THEN** the registry SHALL consider that signal alongside other eligible strategy signals and still resolve the final entry through centralized selection

#### Scenario: Existing position still blocks duplicate strategy entries
- **WHEN** the EA already has an open managed position for the current symbol and MagicNumber
- **THEN** the system SHALL continue to block new spike momentum entries just as it blocks other strategy entries

#### Scenario: Centralized flow preserves full logging context
- **WHEN** the spike momentum strategy is evaluated or blocked in the centralized selection flow
- **THEN** the system SHALL preserve enough context for complete trigger and rejection logging, including position-blocked and selection-blocked outcomes
