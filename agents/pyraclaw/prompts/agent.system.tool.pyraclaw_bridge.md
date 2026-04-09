### pyraclaw_bridge:
Bridge to the PyraClaw ecosystem (DD7 International GmbH). Supports three actions:
- **seal_evidence**: Seal content to the QDP Evidence Ledger. Requires "content" arg; optional "category" (default: agent_output).
- **swarm_status**: Register with the Diamond Army Swarm Manager and retrieve current swarm status. No extra args required.
- **quality_score**: Request an RSFS quality score for content. Requires "content" arg.

**Seal evidence example**:
~~~json
{
    "thoughts": [
        "I have produced a significant finding that should be sealed to the Evidence Ledger for provenance tracking."
    ],
    "headline": "Sealing research finding to PyraClaw Evidence Ledger",
    "tool_name": "pyraclaw_bridge",
    "tool_args": {
        "action": "seal_evidence",
        "content": "Analysis confirms the vulnerability exists in version 2.3.1...",
        "category": "research_finding"
    }
}
~~~

**Swarm status example**:
~~~json
{
    "thoughts": [
        "I should check the Diamond Army swarm status and register my presence."
    ],
    "headline": "Checking PyraClaw swarm status",
    "tool_name": "pyraclaw_bridge",
    "tool_args": {
        "action": "swarm_status"
    }
}
~~~

**Quality score example**:
~~~json
{
    "thoughts": [
        "Before delivering this report I should get an RSFS quality score."
    ],
    "headline": "Requesting RSFS quality score",
    "tool_name": "pyraclaw_bridge",
    "tool_args": {
        "action": "quality_score",
        "content": "The complete report text to be scored..."
    }
}
~~~