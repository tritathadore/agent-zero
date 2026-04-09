import os
import hashlib
import asyncio
from datetime import datetime, timezone

from python.helpers.extension import Extension
from python.helpers.tool import Response
from python.helpers.print_style import PrintStyle

EVIDENCE_LEDGER_URL = os.environ.get("PYRACLAW_EVIDENCE_URL", "http://localhost:8009")
QDP_SUPER_HASH = "9146ce69652472be6ab914e84d2ff76fa64b6ae71c19a0365858c73ee68cda88"


class PyraclawEvidence(Extension):
    """After any tool execution, optionally log the result to the PyraClaw Evidence Ledger.

    Only activates when the environment variable PYRACLAW_EVIDENCE=true is set.
    Runs as a fire-and-forget background task so it never blocks the main agent flow.
    """

    async def execute(self, response: Response | None = None, **kwargs):
        if not response:
            return

        if os.environ.get("PYRACLAW_EVIDENCE", "").lower() != "true":
            return

        # Fire and forget -- do not await, so the main loop is not blocked
        asyncio.create_task(self._log_evidence(response, kwargs))

    async def _log_evidence(self, response: Response, kwargs: dict):
        try:
            import aiohttp

            tool_name = kwargs.get("tool_name", "unknown")

            content_hash = hashlib.sha256(response.message.encode("utf-8")).hexdigest()
            payload = {
                "content": response.message[:4096],  # cap payload size
                "content_hash": content_hash,
                "category": "tool_result",
                "tool_name": tool_name,
                "agent": self.agent.agent_name if self.agent else "unknown",
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "qdp_super_hash": QDP_SUPER_HASH,
            }

            timeout = aiohttp.ClientTimeout(total=5)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(f"{EVIDENCE_LEDGER_URL}/seal", json=payload) as resp:
                    if resp.status >= 300:
                        PrintStyle.warning(
                            f"PyraClaw evidence log returned HTTP {resp.status}"
                        )
        except Exception as e:
            # Never let evidence logging break the agent flow
            PrintStyle.warning(f"PyraClaw evidence log failed (non-blocking): {e}")
