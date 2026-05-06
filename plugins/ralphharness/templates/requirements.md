# Requirements: {{FEATURE_NAME}}

## Goal

{{1-2 sentence description of what this feature accomplishes and why it matters}}

## User Stories

### US-1: {{Story Title}}

**As a** {{user type}}
**I want to** {{action/capability}}
**So that** {{benefit/value}}

**Acceptance Criteria:**
- AC-1.1: {{Specific, testable criterion}}
- AC-1.2: {{Specific, testable criterion}}

### US-2: {{Story Title}}

**As a** {{user type}}
**I want to** {{action/capability}}
**So that** {{benefit/value}}

**Acceptance Criteria:**
- AC-2.1: {{Specific, testable criterion}}
- AC-2.2: {{Specific, testable criterion}}

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-1 | {{description}} | High | {{how to verify}} |
| FR-2 | {{description}} | Medium | {{how to verify}} |
| FR-3 | {{description}} | Low | {{how to verify}} |

## Non-Functional Requirements

| ID | Requirement | Metric | Target |
|----|-------------|--------|--------|
| NFR-1 | Performance | {{metric}} | {{target value}} |
| NFR-2 | Reliability | {{metric}} | {{target value}} |
| NFR-3 | Security | {{standard}} | {{compliance level}} |

## Glossary

- **{{Term 1}}**: {{Definition relevant to this feature}}
- **{{Term 2}}**: {{Another domain-specific term}}

## Out of Scope

- {{Item explicitly not included in this implementation}}
- {{Another exclusion to prevent scope creep}}

## Dependencies

- {{External dependency or prerequisite}}
- {{Another dependency}}

## Success Criteria

- {{Measurable outcome that defines success}}
- {{Another measurable outcome}}

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| {{Risk 1}} | High/Medium/Low | {{How to mitigate}} |
| {{Risk 2}} | High/Medium/Low | {{How to mitigate}} |

## Verification Contract

> Populated by product-manager agent. Tells qa-engineer *what to observe*, not *how to test*.

**Project type**: {{fullstack | frontend | api-only | cli | library}}

**Entry points**: {{routes, endpoints, UI surfaces this story touches}}

**Observable signals**:
- PASS looks like: {{HTTP status / visible element / persisted data / log output}}
- FAIL looks like: {{what wrong state is observable}}

**Hard invariants**: {{what must NEVER break — auth, permissions, adjacent flows}}

**Seed data**: {{minimum system state needed to verify — user role, existing records, config flags}}

**Dependency map**: {{other specs/modules that share state with this one}}

**Escalate if**: {{conditions that require human judgment before proceeding}}
