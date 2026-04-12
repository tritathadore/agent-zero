import os
import json
import hashlib
import time
from datetime import datetime, timezone

import aiohttp
from python.helpers.tool import Tool, Response
from python.helpers.print_style import PrintStyle


# PyraClaw service endpoints
EVIDENCE_LEDGER_URL = os.environ.get("PYRACLAW_EVIDENCE_URL", "http://localhost:8009")
SWARM_MANAGER_URL = os.environ.get("PYRACLAW_SWARM_URL", "http://localhost:8005")
RSFS_CORE_URL = os.environ.get("PYRACLAW_RSFS_URL", "http://localhost:8006")

# Patent and identity constants
PATENT_REF = "PCT/EP2025/080977"
ORCID = "0009-0001-9561-5483"
QDP_SUPER_HASH = "9146ce69652472be6ab914e84d2ff76fa64b6ae71c19a0365858c73ee68cda88"

REQUEST_TIMEOUT = aiohttp.ClientTimeout(total=10)


class PyraclawBridge(Tool):
    """Bridge tool connecting Pyraclaw to the PyraClaw ecosystem.

    Supports three actions:
      - seal_evidence: Create a QDP-sealed evidence record via the Evidence Ledger.
      - swarm_status: Query the Swarm Manager for current swarm state and register presence.
      - quality_score: Request an RSFS quality score for a given payload.
    """

    async def execute(self, **kwargs) -> Response:
        action = self.args.get("action", "").strip().lower()

        if action == "seal_evidence":
            return await self._seal_evidence()
        elif action == "swarm_status":
            return await self._swarm_status()
        elif action == "quality_score":
            return await self._quality_score()
        else:
            return Response(
                message=f"Unknown pyraclaw_bridge action '{action}'. "
                        "Supported actions: seal_evidence, swarm_status, quality_score",
                break_loop=False,
            )

    # ------------------------------------------------------------------
    # seal_evidence
    # ------------------------------------------------------------------
    async def _seal_evidence(self) -> Response:
        content = self.args.get("content", "")
        category = self.args.get("category", "agent_output")
        if not content:
            return Response(message="seal_evidence requires a non-empty 'content' argument.", break_loop=False)

        content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
        payload = {
            "content": content,
            "content_hash": content_hash,
            "category": category,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "agent": self.agent.agent_name,
            "patent": PATENT_REF,
            "qdp_super_hash": QDP_SUPER_HASH,
        }

        try:
            async with aiohttp.ClientSession(timeout=REQUEST_TIMEOUT) as session:
                async with session.post(f"{EVIDENCE_LEDGER_URL}/seal", json=payload) as resp:
                    body = await resp.text()
                    if resp.status < 300:
                        return Response(
                            message=f"Evidence sealed successfully.\nLedger response: {body}",
                            break_loop=False,
                        )
                    else:
                        return Response(
                            message=f"Evidence Ledger returned HTTP {resp.status}: {body}",
                            break_loop=False,
                        )
        except Exception as e:
            PrintStyle.error(f"PyraClaw Evidence Ledger error: {e}")
            return Response(
                message=f"Failed to reach Evidence Ledger at {EVIDENCE_LEDGER_URL}: {e}",
                break_loop=False,
            )

    # ------------------------------------------------------------------
    # swarm_status
    # ------------------------------------------------------------------
    async def _swarm_status(self) -> Response:
        register_payload = {
            "agent_name": self.agent.agent_name,
            "agent_number": self.agent.number,
            "framework": "pyraclaw",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        try:
            async with aiohttp.ClientSession(timeout=REQUEST_TIMEOUT) as session:
                # Register presence with Swarm Manager
                async with session.post(f"{SWARM_MANAGER_URL}/register", json=register_payload) as reg_resp:
                    reg_body = await reg_resp.text()

                # Query current swarm status
                async with session.get(f"{SWARM_MANAGER_URL}/status") as status_resp:
                    status_body = await status_resp.text()

                return Response(
                    message=f"Swarm registration: {reg_body}\nSwarm status: {status_body}",
                    break_loop=False,
                )
        except Exception as e:
            PrintStyle.error(f"PyraClaw Swarm Manager error: {e}")
            return Response(
                message=f"Failed to reach Swarm Manager at {SWARM_MANAGER_URL}: {e}",
                break_loop=False,
            )

    # ------------------------------------------------------------------
    # quality_score
    # ------------------------------------------------------------------
    async def _quality_score(self) -> Response:
        payload_text = self.args.get("content", "")
        if not payload_text:
            return Response(message="quality_score requires a non-empty 'content' argument.", break_loop=False)

        payload = {
            "content": payload_text,
            "agent": self.agent.agent_name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        try:
            async with aiohttp.ClientSession(timeout=REQUEST_TIMEOUT) as session:
                async with session.post(f"{RSFS_CORE_URL}/score", json=payload) as resp:
                    body = await resp.text()
                    if resp.status < 300:
                        return Response(
                            message=f"RSFS quality score response: {body}",
                            break_loop=False,
                        )
                    else:
                        return Response(
                            message=f"RSFS Core returned HTTP {resp.status}: {body}",
                            break_loop=False,
                        )
        except Exception as e:
            PrintStyle.error(f"PyraClaw RSFS Core error: {e}")
            return Response(
                message=f"Failed to reach RSFS Core at {RSFS_CORE_URL}: {e}",
                break_loop=False,
            )
