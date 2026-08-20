# Executable behavior contracts

Use `.feature` files as the shared boundary between discovery and TDD.

Ground this guidance in Cucumber's canonical
[BDD overview](https://cucumber.io/docs/bdd/) and
[Gherkin reference](https://cucumber.io/docs/gherkin/reference/). BDD focuses
collaboration on concrete, real-world examples of desired behavior. Gherkin
gives those examples structure as executable specifications: each scenario
illustrates a business rule through an initial context, an event, and an
observable outcome. A `.feature` file records shared discovery; it does not
replace the conversation or an appropriate wider test suite.

## Contract

- Name features and scenarios as capabilities, not functions or files.
- Put only common preconditions in `Background`.
- Use `Given` for state, `When` for the action, and `Then` for observable
  results or durable invariants.
- Cover the valuable path plus applicable invariants, no-op/idempotent behavior,
  isolation or partitioning, boundaries, and explicitly rejected syntax or
  scope.
- Prefer explicit example tables and literal expected values.
- Keep implementation details out of steps.
- Reuse existing steps before adding narrowly named new ones.
- A scenario is an automated test only when bound to runnable steps and observed
  failing before implementation. Otherwise label it as an unautomated contract.
- Do not add a BDD dependency only to parse prose. Bind scenarios through the
  repository's existing acceptance-test harness when possible.

## Minimal shape

```gherkin
Feature: <user-visible capability>

  Background:
    Given <shared state>

  Scenario: <observable behavior>
    Given <specific state>
    When <user or system action>
    Then <observable result>
    And <preserved invariant>

  Scenario: <repeat or boundary behavior>
    Given <boundary state>
    When <action>
    Then <observable result>
```

Place the file beside existing acceptance features. If none exist, the plan
must name its intended runner and step-binding location before implementation.
In a coordination repository, place the executable feature in the repository
that owns the behavior and link it from the cross-repository proposal.
