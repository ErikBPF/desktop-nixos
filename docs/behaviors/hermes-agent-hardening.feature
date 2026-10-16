Feature: Preserve evidence and restrict webhook execution without changing operator workflows
  # Accepted seed and choices: homelab delivery one-pager, 2026-10-14, revision 2.
  # Plugin scenarios bind to each plugin's stdlib selftest.py; configuration
  # assertions and native-dispatch receipts are recorded in the owner one-pager.

  Scenario: Rewrite only terminal commands successfully and privately
    Given an exact terminal tool call with an unwrapped command
    When RTK returns a changed command with exit status zero
    Then the native modify directive replaces only the command argument
    And command text is absent from plugin logs
    And unrelated tools, already wrapped commands, failures and timeouts remain unchanged

  Scenario: Preserve closed quoted evidence while removing naked leaks
    Given closed inline code, backtick or tilde fences, blockquotes or prose quotations
    When evidence and unquoted tool-call leakage occur together
    Then quoted evidence outside unfinished naked payloads remains byte-faithful
    And unquoted full or truncated leakage is removed
    And malformed unclosed quotations confer no exemption
    And quotations inside naked payloads do not exempt the outer payload
    And JSON and Python tool-call object keys and values are syntax, not quoted evidence
    And nested same-name XML and truncated attributes are classified before inner quotations
    And escaped inline backtick delimiters confer no exemption
    And quoted-only evidence does not become NO_REPLY

  # Explicit user choice Q-GUARD-TRUNC-BOUNDARY: "Fail closed (Recommended)".
  Scenario: Fail closed through the end of unfinished naked tool XML
    Given an unquoted tool XML opener or attribute with no complete envelope boundary
    When closed quotations or Markdown evidence occur on following lines
    Then the unfinished envelope owns the remaining message
    And its payload quotations confer no evidence exemption
    And evidence before it, after complete envelopes, or wholly quoted structures remains byte-faithful

  Scenario: Limit Romozinha webhook ingress only
    When Discovery configuration is evaluated
    Then Romozinha healthcheck is enabled
    And its webhook platform toolset is empty
    And Discord and Telegram toolsets, allowlists, approval mode and YOLO remain unchanged
