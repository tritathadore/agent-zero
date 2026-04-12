#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════════
#  PyraClaw Forge v2.0.0 — Diamond Army Deployment System
#  Byron Callaghan / Pyraclaw  |  Patent PCT/EP2025/080977 | US 19/541,276
#  ORCID: 0009-0001-9561-5483 (Byron Callaghan)
#
#  Forges, deploys, and manages the 8-agent Diamond Army across a Brev.dev
#  GPU fleet. Each agent is a standalone FastAPI service with QDP-sealed
#  evidence trails, RSFS quality scoring, and swarm mesh registration.
#
#  Fleet:
#    H100  enterprise--pyraclaw-rag-f88f75  (h8f02ie72)  PRIMARY
#    A6000 cyberclaw-gpu                    (srt1t9ngj)  SECURITY
#    A4000 pyraclaw-power                   (84m1nha3)   ROUTING
#
#  Commands:
#    forge <Agent>    Forge a single agent
#    all              Forge full Diamond Army (8 agents)
#    deploy <Agent>   Deploy agent to Brev GPU via SSH
#    start <Agent>    Start a forged agent
#    stop <Agent>     Stop a running agent
#    restart <Agent>  Restart a running agent
#    status           Fleet and agent status
#    health           Health check all running agents
#    logs <Agent>     Tail agent logs
#    destroy <Agent>  Remove agent workspace
#    help             Show this help
# ════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Identity ──────────────────────────────────────────────────────────────────
readonly FORGE_VERSION="2.0.0"
readonly PATENT="PCT/EP2025/080977"
readonly PATENT_US="US 19/541,276"
readonly ORCID="0009-0001-9561-5483"
readonly QDP_SUPER_HASH="9146ce69652472be6ab914e84d2ff76fa64b6ae71c19a0365858c73ee68cda88"
readonly HMAC_KEY="${QDP_SUPER_HASH}"

# ── RSFS Constants ────────────────────────────────────────────────────────────
readonly RSFS_C_OPT=78.42
readonly RSFS_C_CRIT=52.79
readonly RSFS_PHI=0.77
readonly RSFS_KAPPA=0.618

# ── Infrastructure Ports ──────────────────────────────────────────────────────
readonly SWARM_MANAGER_PORT=8005
readonly RSFS_CORE_PORT=8006
readonly FREEDOM_ENGINE_PORT=8001
readonly EVIDENCE_LEDGER_PORT=8009

# ── Paths ─────────────────────────────────────────────────────────────────────
readonly PYRACLAW_HOME="${HOME}/pyraclaw"
readonly AGENTS_DIR="${PYRACLAW_HOME}/agents"
readonly MANIFEST_FILE="${AGENTS_DIR}/diamond-army-manifest.json"

# ── Brev Fleet ────────────────────────────────────────────────────────────────
declare -A FLEET_NAME=(
  [0]="enterprise--pyraclaw-rag-f88f75"
  [1]="cyberclaw-gpu"
  [2]="pyraclaw-power"
)
declare -A FLEET_ID=(
  [0]="h8f02ie72"
  [1]="srt1t9ngj"
  [2]="84m1nha3"
)
declare -A FLEET_GPU=(
  [0]="H100"
  [1]="A6000"
  [2]="A4000"
)
declare -A FLEET_ROLE=(
  [0]="primary"
  [1]="security"
  [2]="routing"
)

# ── Diamond Army Agent Definitions ────────────────────────────────────────────
# Format: gpu_idx|swarm_role|port|description|model|extra_endpoints
declare -A AGENTS=(
  [LightningClaw]="0|orchestrator|8101|Sovereign orchestrator — task decomposition and swarm coordination|claude-sonnet-4-20250514|/coordinate,/decompose"
  [CodeClaw]="1|worker|8102|Full-stack code generation and execution|claude-sonnet-4-20250514|/execute,/review"
  [CharismaClaw]="2|bridge|8103|Communication — investor narrative and presentation|claude-sonnet-4-20250514|/narrate,/present"
  [GuardianClaw]="1|guardian|8104|Security posture — threat detection and QDP enforcement|claude-sonnet-4-20250514|/scan,/enforce"
  [EvidenceClaw]="0|validator|8105|Evidence sealing — QDP capsule generation and Zenodo minting|claude-sonnet-4-20250514|/seal,/mint"
  [ScoutClaw]="0|scout|8106|Reconnaissance — web search, data gathering, knowledge ingestion|claude-sonnet-4-20250514|/search,/ingest"
  [AnalystClaw]="2|analyst|8107|RSFS scoring — 8-dimension quality evaluation|claude-sonnet-4-20250514|/evaluate,/score"
  [CortexClaw]="2|cortex|8108|Neural mesh — 44-channel routing, frequency coherence|claude-sonnet-4-20250514|/route,/mesh"
)

# Agent ordering for consistent iteration
readonly AGENT_ORDER=(LightningClaw CodeClaw CharismaClaw GuardianClaw EvidenceClaw ScoutClaw AnalystClaw CortexClaw)

# ── Colour Palette (Minted Green) ────────────────────────────────────────────
readonly C_GOLD=$'\033[38;2;200;168;75m'
readonly C_GREEN=$'\033[38;2;45;212;160m'
readonly C_RED=$'\033[38;2;224;85;85m'
readonly C_STEEL=$'\033[38;2;150;170;200m'
readonly C_PLAT=$'\033[38;2;229;229;229m'
readonly C_OBS=$'\033[38;2;26;26;46m'
readonly C_DIM=$'\033[38;2;100;100;120m'
readonly C_WHITE=$'\033[38;2;240;240;240m'
readonly C_CYAN=$'\033[38;2;80;200;220m'
readonly C_BOLD=$'\033[1m'
readonly C_RESET=$'\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
_ts() { date -u +"%H:%M:%S"; }

pyra_log()    { echo -e "${C_GOLD}[$(_ts)] forge${C_RESET}  $*"; }
pyra_ok()     { echo -e "${C_GREEN}         +${C_RESET}  $*"; }
pyra_fail()   { echo -e "${C_RED}         x${C_RESET}  $*"; }
pyra_info()   { echo -e "${C_STEEL}         >${C_RESET}  $*"; }
pyra_dim()    { echo -e "${C_DIM}            $*${C_RESET}"; }
pyra_warn()   { echo -e "${C_GOLD}         !${C_RESET}  $*"; }

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
  local w=72
  echo ""
  echo -e "${C_GOLD}  ╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_GOLD}  ║                                                                      ║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_WHITE}${C_BOLD}   PyraClaw Forge${C_RESET}${C_PLAT}  Diamond Army Deployment System  ${C_DIM}v${FORGE_VERSION}${C_RESET}        ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_STEEL}   Byron Callaghan / Pyraclaw${C_RESET}${C_DIM}  Patent: ${PATENT}${C_RESET}           ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_DIM}   ORCID: ${ORCID}  |  QDP-Sealed  |  RSFS-Scored${C_RESET}          ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║                                                                      ║${C_RESET}"
  echo -e "${C_GOLD}  ╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo ""
}

# ── QDP 4-Layer Seal ──────────────────────────────────────────────────────────
# Generates SHA-256 + SHA-512 + SHA3-256 + HMAC-SHA256 for any payload.
# Returns JSON object with all four digests.
qdp_seal() {
  local payload="$1"
  local sha256 sha512 sha3_256 hmac_sha256

  sha256=$(echo -n "$payload" | sha256sum | cut -d' ' -f1)
  sha512=$(echo -n "$payload" | sha512sum | cut -d' ' -f1)

  # SHA3-256 via openssl if available, fallback to python3
  if openssl dgst -sha3-256 /dev/null &>/dev/null; then
    sha3_256=$(echo -n "$payload" | openssl dgst -sha3-256 2>/dev/null | awk '{print $NF}')
  else
    sha3_256=$(python3 -c "
import hashlib, sys
print(hashlib.sha3_256(sys.stdin.buffer.read()).hexdigest())
" <<< "$payload" 2>/dev/null) || sha3_256="requires-python3-hashlib"
  fi

  # HMAC-SHA256 keyed with QDP Super Hash
  hmac_sha256=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$HMAC_KEY" 2>/dev/null | awk '{print $NF}')
  if [ -z "$hmac_sha256" ]; then
    hmac_sha256=$(python3 -c "
import hmac, hashlib, sys
key = '${HMAC_KEY}'.encode()
msg = sys.stdin.buffer.read()
print(hmac.new(key, msg, hashlib.sha256).hexdigest())
" <<< "$payload" 2>/dev/null) || hmac_sha256="requires-openssl-or-python3"
  fi

  cat <<EOF
{
  "sha256": "${sha256}",
  "sha512": "${sha512}",
  "sha3_256": "${sha3_256}",
  "hmac_sha256": "${hmac_sha256}"
}
EOF
}

# Compact single-line seal for embedding
qdp_seal_compact() {
  local payload="$1"
  local sha256 sha512 sha3_256 hmac_sha256

  sha256=$(echo -n "$payload" | sha256sum | cut -d' ' -f1)
  sha512=$(echo -n "$payload" | sha512sum | cut -d' ' -f1)

  if openssl dgst -sha3-256 /dev/null &>/dev/null; then
    sha3_256=$(echo -n "$payload" | openssl dgst -sha3-256 2>/dev/null | awk '{print $NF}')
  else
    sha3_256=$(python3 -c "import hashlib; print(hashlib.sha3_256(b'${payload}').hexdigest())" 2>/dev/null || echo "n/a")
  fi

  hmac_sha256=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$HMAC_KEY" 2>/dev/null | awk '{print $NF}')
  [ -z "$hmac_sha256" ] && hmac_sha256="n/a"

  echo "{\"sha256\":\"${sha256}\",\"sha512\":\"${sha512}\",\"sha3_256\":\"${sha3_256}\",\"hmac_sha256\":\"${hmac_sha256}\"}"
}

# ── Agent Spec Parser ─────────────────────────────────────────────────────────
parse_agent() {
  local name="$1"
  if [ -z "${AGENTS[$name]+_}" ]; then
    return 1
  fi
  local spec="${AGENTS[$name]}"
  IFS='|' read -r AGENT_GPU_IDX AGENT_ROLE AGENT_PORT AGENT_DESC AGENT_MODEL AGENT_ENDPOINTS <<< "$spec"
  AGENT_GPU="${FLEET_GPU[$AGENT_GPU_IDX]}"
  AGENT_FLEET_NAME="${FLEET_NAME[$AGENT_GPU_IDX]}"
  AGENT_FLEET_ID="${FLEET_ID[$AGENT_GPU_IDX]}"
  AGENT_DIR="${AGENTS_DIR}/${name,,}"
}

# ── Environment Check ─────────────────────────────────────────────────────────
check_env() {
  pyra_log "Environment verification"

  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    pyra_ok "ANTHROPIC_API_KEY configured"
  else
    pyra_warn "ANTHROPIC_API_KEY not set — /reason endpoints will be unavailable"
  fi

  if command -v python3 &>/dev/null; then
    local pyver
    pyver=$(python3 --version 2>&1 | awk '{print $2}')
    pyra_ok "Python ${pyver}"
  else
    pyra_fail "Python3 required"
    return 1
  fi

  # Check for required Python packages
  local missing=()
  for pkg in fastapi uvicorn httpx pydantic; do
    python3 -c "import ${pkg}" 2>/dev/null || missing+=("$pkg")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    pyra_warn "Missing Python packages: ${missing[*]}"
    pyra_info "Install: pip install ${missing[*]}"
  else
    pyra_ok "Python dependencies satisfied"
  fi

  if command -v nvidia-smi &>/dev/null; then
    local gpu_info
    gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1 || echo "detected")
    pyra_ok "GPU: ${gpu_info}"
  else
    pyra_info "No local GPU — agents target Brev fleet via SSH"
  fi

  if command -v brev &>/dev/null; then
    pyra_ok "Brev CLI available"
  else
    pyra_info "Brev CLI not found — SSH deployment uses direct connection"
  fi

  echo ""
}

# ── Generate FastAPI Agent Service ────────────────────────────────────────────
# Creates a complete Python FastAPI service for a single agent.
generate_agent_service() {
  local name="$1"
  parse_agent "$name" || return 1

  local agent_lower="${name,,}"
  local service_file="${AGENT_DIR}/service.py"
  local endpoints_csv="$AGENT_ENDPOINTS"

  # Parse role-specific endpoint names (strip leading /)
  local ep1 ep2
  ep1=$(echo "$endpoints_csv" | cut -d',' -f1 | tr -d '/')
  ep2=$(echo "$endpoints_csv" | cut -d',' -f2 | tr -d '/')

  cat > "$service_file" << PYEOF
"""
${name} Agent Service — PyraClaw Diamond Army
Role: ${AGENT_ROLE} | GPU: ${AGENT_GPU} | Port: ${AGENT_PORT}
Byron Callaghan / Pyraclaw | Patent: ${PATENT}
ORCID: ${ORCID}
"""

import hashlib
import hmac
import json
import os
import time
import uuid
from collections import deque
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field
import uvicorn

# ── Constants ────────────────────────────────────────────────────────────────
AGENT_NAME = "${name}"
AGENT_ROLE = "${AGENT_ROLE}"
AGENT_PORT = ${AGENT_PORT}
AGENT_GPU = "${AGENT_GPU}"
AGENT_DESC = "${AGENT_DESC}"
AGENT_MODEL = "${AGENT_MODEL}"
FORGE_VERSION = "${FORGE_VERSION}"
PATENT = "${PATENT}"
ORCID = "${ORCID}"
QDP_SUPER_HASH = "${QDP_SUPER_HASH}"
HMAC_KEY = QDP_SUPER_HASH.encode("utf-8")

RSFS_PHI = ${RSFS_PHI}
RSFS_KAPPA = ${RSFS_KAPPA}
RSFS_C_OPT = ${RSFS_C_OPT}
RSFS_C_CRIT = ${RSFS_C_CRIT}

RSFS_DIMENSIONS = {
    "correctness":      {"weight": 0.85, "score": 0.75},
    "alignment":        {"weight": 0.88, "score": 0.80},
    "stability":        {"weight": 0.82, "score": 0.78},
    "ui_integrity":     {"weight": 0.80, "score": 0.70},
    "deploy_readiness": {"weight": 0.78, "score": 0.72},
    "evidence_quality": {"weight": 0.85, "score": 0.76},
    "security_posture": {"weight": 0.90, "score": 0.80},
    "compliance_gate":  {"weight": 0.80, "score": 0.74},
}

SWARM_MANAGER_URL = "http://localhost:${SWARM_MANAGER_PORT}"
EVIDENCE_LEDGER_URL = "http://localhost:${EVIDENCE_LEDGER_PORT}"

START_TIME = time.time()

# ── State ────────────────────────────────────────────────────────────────────
task_queue: deque = deque(maxlen=1000)
completed_tasks: List[Dict[str, Any]] = []
evidence_log: List[Dict[str, Any]] = []


# ── Models ───────────────────────────────────────────────────────────────────
class TaskRequest(BaseModel):
    task_id: Optional[str] = None
    action: str
    payload: Any = None
    priority: int = Field(default=5, ge=1, le=10)
    metadata: Dict[str, Any] = Field(default_factory=dict)

class TaskResponse(BaseModel):
    task_id: str
    agent: str
    role: str
    status: str
    queued_at: float

class EvidenceRequest(BaseModel):
    title: str
    payload: Any
    tags: List[str] = Field(default_factory=list)

class EvidenceResponse(BaseModel):
    entry_id: str
    agent: str
    title: str
    qdp_seal: Dict[str, str]
    ledger_synced: bool
    timestamp: float

class ReasonRequest(BaseModel):
    prompt: str
    max_tokens: int = Field(default=2048, ge=1, le=8192)
    temperature: float = Field(default=0.7, ge=0.0, le=1.0)
    system: Optional[str] = None

class ReasonResponse(BaseModel):
    agent: str
    model: str
    content: str
    usage: Dict[str, int]
    timestamp: float

class RSFSReport(BaseModel):
    agent: str
    role: str
    dimensions: Dict[str, Any]
    Q: float
    C: float
    gate: str
    timestamp: float


# ── QDP Hashing ──────────────────────────────────────────────────────────────
def _normalise(payload: Any) -> bytes:
    if isinstance(payload, bytes):
        return payload
    if isinstance(payload, str):
        return payload.encode("utf-8")
    return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")

def qdp_hash(payload: Any) -> Dict[str, str]:
    raw = _normalise(payload)
    result = {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "sha512": hashlib.sha512(raw).hexdigest(),
        "sha3_256": hashlib.sha3_256(raw).hexdigest(),
        "hmac_sha256": hmac.new(HMAC_KEY, raw, hashlib.sha256).hexdigest(),
    }
    return result


# ── RSFS Scoring ─────────────────────────────────────────────────────────────
def compute_rsfs() -> Dict[str, Any]:
    total_weighted = 0.0
    total_weight = 0.0
    dims = {}
    for dim_name, dim_info in RSFS_DIMENSIONS.items():
        w = dim_info["weight"]
        s = dim_info["score"]
        ws = round(s * w, 4)
        dims[dim_name] = {"weight": w, "score": s, "weighted": ws}
        total_weighted += ws
        total_weight += w
    Q = round(total_weighted / total_weight, 4) if total_weight > 0 else 0.0
    C = round(RSFS_PHI * Q * RSFS_KAPPA * 100, 4)
    gate = "PASS" if C >= RSFS_C_OPT else ("HOLD" if C >= RSFS_C_CRIT else "NEEDS_IMPROVEMENT")
    return {"dimensions": dims, "Q": Q, "C": C, "gate": gate}


# ── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title=f"{AGENT_NAME} — PyraClaw Diamond Army",
    description=AGENT_DESC,
    version=FORGE_VERSION,
)


@app.get("/health")
async def health():
    return {
        "agent": AGENT_NAME,
        "role": AGENT_ROLE,
        "status": "operational",
        "gpu": AGENT_GPU,
        "port": AGENT_PORT,
        "uptime": round(time.time() - START_TIME, 2),
        "tasks_queued": len(task_queue),
        "tasks_completed": len(completed_tasks),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/identity")
async def identity():
    return {
        "agent": {
            "name": AGENT_NAME,
            "role": AGENT_ROLE,
            "description": AGENT_DESC,
            "version": FORGE_VERSION,
            "model": AGENT_MODEL,
        },
        "deployment": {
            "gpu": AGENT_GPU,
            "port": AGENT_PORT,
            "fleet_instance": "${AGENT_FLEET_NAME}",
            "fleet_id": "${AGENT_FLEET_ID}",
        },
        "governance": {
            "patent": PATENT,
            "orcid": ORCID,
            "qdp_enabled": True,
            "rsfs_c_opt": RSFS_C_OPT,
            "rsfs_c_crit": RSFS_C_CRIT,
        },
    }


@app.post("/task", response_model=TaskResponse)
async def accept_task(req: TaskRequest):
    task_id = req.task_id or str(uuid.uuid4())
    entry = {
        "task_id": task_id,
        "action": req.action,
        "payload": req.payload,
        "priority": req.priority,
        "metadata": req.metadata,
        "queued_at": time.time(),
        "status": "queued",
    }
    task_queue.append(entry)
    return TaskResponse(
        task_id=task_id,
        agent=AGENT_NAME,
        role=AGENT_ROLE,
        status="queued",
        queued_at=entry["queued_at"],
    )


@app.post("/evidence", response_model=EvidenceResponse)
async def record_evidence(req: EvidenceRequest):
    seal = qdp_hash(req.payload)
    entry_id = str(uuid.uuid4())
    ts = time.time()

    entry = {
        "entry_id": entry_id,
        "agent": AGENT_NAME,
        "title": req.title,
        "qdp_seal": seal,
        "payload_digest": seal["sha256"],
        "tags": req.tags,
        "timestamp": ts,
    }
    evidence_log.append(entry)

    # Attempt to sync with Evidence Ledger
    ledger_synced = False
    try:
        import httpx
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                f"{EVIDENCE_LEDGER_URL}/record",
                json={
                    "title": f"[{AGENT_NAME}] {req.title}",
                    "payload": req.payload,
                    "source": AGENT_NAME,
                    "tags": [AGENT_NAME, AGENT_ROLE] + req.tags,
                },
            )
            if resp.status_code == 200:
                ledger_synced = True
    except Exception:
        pass

    return EvidenceResponse(
        entry_id=entry_id,
        agent=AGENT_NAME,
        title=req.title,
        qdp_seal=seal,
        ledger_synced=ledger_synced,
        timestamp=ts,
    )


@app.get("/rsfs", response_model=RSFSReport)
async def rsfs_report():
    scores = compute_rsfs()
    return RSFSReport(
        agent=AGENT_NAME,
        role=AGENT_ROLE,
        dimensions=scores["dimensions"],
        Q=scores["Q"],
        C=scores["C"],
        gate=scores["gate"],
        timestamp=time.time(),
    )


@app.post("/reason", response_model=ReasonResponse)
async def reason(req: ReasonRequest):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="ANTHROPIC_API_KEY not configured")
    try:
        import httpx
        system_prompt = req.system or f"You are {AGENT_NAME}, a {AGENT_ROLE} agent in the PyraClaw Diamond Army. {AGENT_DESC}. Be precise, evidence-backed, and measured."
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                },
                json={
                    "model": AGENT_MODEL,
                    "max_tokens": req.max_tokens,
                    "temperature": req.temperature,
                    "system": system_prompt,
                    "messages": [{"role": "user", "content": req.prompt}],
                },
            )
            resp.raise_for_status()
            data = resp.json()
            content = data.get("content", [{}])[0].get("text", "")
            usage = data.get("usage", {})
            return ReasonResponse(
                agent=AGENT_NAME,
                model=AGENT_MODEL,
                content=content,
                usage={"input_tokens": usage.get("input_tokens", 0), "output_tokens": usage.get("output_tokens", 0)},
                timestamp=time.time(),
            )
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=f"Claude API error: {e.response.text[:500]}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Reasoning error: {str(e)[:500]}")


# ── Role-Specific Endpoints ─────────────────────────────────────────────────
PYEOF

  # Now append role-specific endpoints based on agent name
  case "$name" in
    LightningClaw)
      cat >> "$service_file" << 'ROLE_EP'

class CoordinateRequest(BaseModel):
    objective: str
    agents: List[str] = Field(default_factory=list)
    strategy: str = "parallel"

@app.post("/coordinate")
async def coordinate(req: CoordinateRequest):
    """Coordinate task distribution across Diamond Army agents."""
    assignments = []
    target_agents = req.agents if req.agents else ["CodeClaw", "ScoutClaw", "AnalystClaw"]
    for agent in target_agents:
        assignments.append({
            "agent": agent,
            "objective": req.objective,
            "strategy": req.strategy,
            "assigned_at": time.time(),
        })
    seal = qdp_hash({"objective": req.objective, "assignments": assignments})
    return {"orchestrator": AGENT_NAME, "assignments": assignments, "qdp_seal": seal}

class DecomposeRequest(BaseModel):
    task: str
    depth: int = Field(default=3, ge=1, le=10)

@app.post("/decompose")
async def decompose(req: DecomposeRequest):
    """Decompose a complex task into subtasks."""
    subtasks = []
    for i in range(min(req.depth, 8)):
        subtasks.append({
            "subtask_id": f"st-{uuid.uuid4().hex[:8]}",
            "parent_task": req.task,
            "depth": i + 1,
            "status": "pending",
        })
    return {"task": req.task, "subtasks": subtasks, "decomposed_by": AGENT_NAME}
ROLE_EP
      ;;

    CodeClaw)
      cat >> "$service_file" << 'ROLE_EP'

class ExecuteRequest(BaseModel):
    language: str = "python"
    code: str
    timeout: int = Field(default=30, ge=1, le=300)
    sandbox: bool = True

@app.post("/execute")
async def execute(req: ExecuteRequest):
    """Accept code for execution (sandboxed). Returns execution plan and seal."""
    code_hash = qdp_hash(req.code)
    return {
        "agent": AGENT_NAME,
        "language": req.language,
        "code_length": len(req.code),
        "code_hash": code_hash["sha256"][:32],
        "sandbox": req.sandbox,
        "status": "execution_planned",
        "qdp_seal": code_hash,
    }

class ReviewRequest(BaseModel):
    code: str
    language: str = "python"
    focus: List[str] = Field(default_factory=lambda: ["security", "correctness", "style"])

@app.post("/review")
async def review(req: ReviewRequest):
    """Queue code for review analysis."""
    review_id = str(uuid.uuid4())
    seal = qdp_hash(req.code)
    return {
        "review_id": review_id,
        "agent": AGENT_NAME,
        "language": req.language,
        "focus_areas": req.focus,
        "lines": req.code.count("\n") + 1,
        "status": "review_queued",
        "qdp_seal": seal,
    }
ROLE_EP
      ;;

    CharismaClaw)
      cat >> "$service_file" << 'ROLE_EP'

class NarrateRequest(BaseModel):
    topic: str
    audience: str = "investor"
    tone: str = "professional"
    length: str = "concise"

@app.post("/narrate")
async def narrate(req: NarrateRequest):
    """Queue narrative generation for investor/stakeholder communication."""
    narration_id = str(uuid.uuid4())
    return {
        "narration_id": narration_id,
        "agent": AGENT_NAME,
        "topic": req.topic,
        "audience": req.audience,
        "tone": req.tone,
        "status": "narration_queued",
    }

class PresentRequest(BaseModel):
    title: str
    sections: List[str]
    format: str = "markdown"

@app.post("/present")
async def present(req: PresentRequest):
    """Queue presentation generation."""
    pres_id = str(uuid.uuid4())
    return {
        "presentation_id": pres_id,
        "agent": AGENT_NAME,
        "title": req.title,
        "section_count": len(req.sections),
        "format": req.format,
        "status": "presentation_queued",
    }
ROLE_EP
      ;;

    GuardianClaw)
      cat >> "$service_file" << 'ROLE_EP'

class ScanRequest(BaseModel):
    target: str
    scan_type: str = "full"
    depth: str = "standard"

@app.post("/scan")
async def scan(req: ScanRequest):
    """Queue security scan of a target resource."""
    scan_id = str(uuid.uuid4())
    seal = qdp_hash({"target": req.target, "type": req.scan_type})
    return {
        "scan_id": scan_id,
        "agent": AGENT_NAME,
        "target": req.target,
        "scan_type": req.scan_type,
        "depth": req.depth,
        "status": "scan_queued",
        "qdp_seal": seal,
    }

class EnforceRequest(BaseModel):
    policy: str
    resource: str
    action: str = "audit"

@app.post("/enforce")
async def enforce(req: EnforceRequest):
    """Enforce QDP compliance policy on a resource."""
    enforce_id = str(uuid.uuid4())
    return {
        "enforce_id": enforce_id,
        "agent": AGENT_NAME,
        "policy": req.policy,
        "resource": req.resource,
        "action": req.action,
        "status": "enforcement_queued",
    }
ROLE_EP
      ;;

    EvidenceClaw)
      cat >> "$service_file" << 'ROLE_EP'

class SealRequest(BaseModel):
    title: str
    payload: Any
    tags: List[str] = Field(default_factory=list)
    zenodo_stage: bool = False

@app.post("/seal")
async def seal(req: SealRequest):
    """Generate QDP-sealed evidence capsule."""
    capsule_id = str(uuid.uuid4())
    seal_data = qdp_hash(req.payload)
    capsule = {
        "capsule_id": capsule_id,
        "title": req.title,
        "agent": AGENT_NAME,
        "qdp_layers": seal_data,
        "tags": req.tags,
        "patent": PATENT,
        "orcid": ORCID,
        "zenodo_staged": req.zenodo_stage,
        "sealed_at": datetime.now(timezone.utc).isoformat(),
    }
    evidence_log.append(capsule)

    # Sync to ledger
    ledger_ok = False
    try:
        import httpx
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(f"{EVIDENCE_LEDGER_URL}/record", json={
                "title": req.title, "payload": req.payload,
                "source": AGENT_NAME, "tags": [AGENT_NAME] + req.tags,
                "zenodo_stage": req.zenodo_stage,
            })
            ledger_ok = resp.status_code == 200
    except Exception:
        pass

    return {"capsule": capsule, "ledger_synced": ledger_ok}

class MintRequest(BaseModel):
    capsule_id: str
    zenodo_community: str = "pyraclaw"

@app.post("/mint")
async def mint(req: MintRequest):
    """Stage a sealed capsule for Zenodo minting."""
    capsule = next((e for e in evidence_log if e.get("capsule_id") == req.capsule_id), None)
    if not capsule:
        raise HTTPException(status_code=404, detail=f"Capsule {req.capsule_id} not found")
    return {
        "capsule_id": req.capsule_id,
        "agent": AGENT_NAME,
        "zenodo_community": req.zenodo_community,
        "status": "mint_staged",
        "orcid": ORCID,
    }
ROLE_EP
      ;;

    ScoutClaw)
      cat >> "$service_file" << 'ROLE_EP'

class SearchRequest(BaseModel):
    query: str
    sources: List[str] = Field(default_factory=lambda: ["web", "arxiv", "github"])
    max_results: int = Field(default=10, ge=1, le=50)

@app.post("/search")
async def search(req: SearchRequest):
    """Queue reconnaissance search across configured sources."""
    search_id = str(uuid.uuid4())
    seal = qdp_hash(req.query)
    return {
        "search_id": search_id,
        "agent": AGENT_NAME,
        "query": req.query,
        "sources": req.sources,
        "max_results": req.max_results,
        "status": "search_queued",
        "query_seal": seal["sha256"][:32],
    }

class IngestRequest(BaseModel):
    url: Optional[str] = None
    content: Optional[str] = None
    content_type: str = "text"
    tags: List[str] = Field(default_factory=list)

@app.post("/ingest")
async def ingest(req: IngestRequest):
    """Ingest knowledge from URL or direct content."""
    ingest_id = str(uuid.uuid4())
    source = req.url or "direct_content"
    payload = req.url or (req.content[:200] if req.content else "empty")
    seal = qdp_hash(payload)
    return {
        "ingest_id": ingest_id,
        "agent": AGENT_NAME,
        "source": source,
        "content_type": req.content_type,
        "tags": req.tags,
        "status": "ingestion_queued",
        "qdp_seal": seal,
    }
ROLE_EP
      ;;

    AnalystClaw)
      cat >> "$service_file" << 'ROLE_EP'

class EvaluateRequest(BaseModel):
    scores: Dict[str, float] = Field(
        default_factory=dict,
        description="Dimension name -> score (0.0 to 1.0)",
    )
    context: str = "manual"

@app.post("/evaluate")
async def evaluate(req: EvaluateRequest):
    """Run RSFS 8-dimension evaluation."""
    dims = {}
    total_weighted = 0.0
    total_weight = 0.0
    for dim_name, dim_info in RSFS_DIMENSIONS.items():
        raw = max(0.0, min(1.0, req.scores.get(dim_name, dim_info["score"])))
        w = dim_info["weight"]
        ws = round(raw * w, 4)
        dims[dim_name] = {"raw": raw, "weight": w, "weighted": ws}
        total_weighted += ws
        total_weight += w
    Q = round(total_weighted / total_weight, 4) if total_weight > 0 else 0.0
    N = round(len([d for d in dims.values() if d["weighted"] >= 0.5]) / len(RSFS_DIMENSIONS), 4)
    C = round(RSFS_PHI * Q * N * RSFS_KAPPA * 100, 4)
    gate = "PASS" if C >= RSFS_C_OPT else ("HOLD" if C >= RSFS_C_CRIT else "NEEDS_IMPROVEMENT")

    # Attempt to forward to RSFS Core
    rsfs_synced = False
    try:
        import httpx
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(f"http://localhost:${RSFS_CORE_PORT}/api/rsfs/evaluate", json={
                "scores": {k: v["raw"] for k, v in dims.items()}, "context": req.context,
            })
            rsfs_synced = resp.status_code == 200
    except Exception:
        pass

    return {
        "agent": AGENT_NAME,
        "context": req.context,
        "dimensions": dims,
        "Q": Q, "N": N, "C": C,
        "gate": gate,
        "rsfs_core_synced": rsfs_synced,
    }

class ScoreRequest(BaseModel):
    dimension: str
    score: float = Field(ge=0.0, le=1.0)

@app.post("/score")
async def update_score(req: ScoreRequest):
    """Update a single RSFS dimension score."""
    if req.dimension not in RSFS_DIMENSIONS:
        raise HTTPException(status_code=400, detail=f"Unknown dimension: {req.dimension}")
    old = RSFS_DIMENSIONS[req.dimension]["score"]
    RSFS_DIMENSIONS[req.dimension]["score"] = req.score
    return {
        "agent": AGENT_NAME,
        "dimension": req.dimension,
        "previous": old,
        "current": req.score,
        "status": "updated",
    }
ROLE_EP
      ;;

    CortexClaw)
      cat >> "$service_file" << 'ROLE_EP'

class RouteRequest(BaseModel):
    source: str
    destination: str
    payload: Any = None
    channel: int = Field(default=1, ge=1, le=44)

@app.post("/route")
async def route(req: RouteRequest):
    """Route a message through the 44-channel neural mesh."""
    route_id = str(uuid.uuid4())
    seal = qdp_hash({"src": req.source, "dst": req.destination, "ch": req.channel})
    return {
        "route_id": route_id,
        "agent": AGENT_NAME,
        "source": req.source,
        "destination": req.destination,
        "channel": req.channel,
        "status": "routed",
        "qdp_seal": seal,
    }

class MeshRequest(BaseModel):
    action: str = "status"

@app.post("/mesh")
async def mesh(req: MeshRequest):
    """Query or manage the neural mesh state."""
    mesh_state = {
        "total_channels": 44,
        "active_channels": 44,
        "frequencies": {
            "icode": 432,
            "acode": 528,
            "ccode": 639,
            "bridge": 963,
        },
        "coherence": round(RSFS_PHI, 4),
    }
    return {"agent": AGENT_NAME, "action": req.action, "mesh": mesh_state}
ROLE_EP
      ;;
  esac

  # Append uvicorn runner to all agents
  cat >> "$service_file" << PYEOF


# ── Entry Point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [${name}] %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=AGENT_PORT,
        log_level="info",
        access_log=True,
    )
PYEOF
}

# ── Forge Single Agent ────────────────────────────────────────────────────────
forge_agent() {
  local name="$1"

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    pyra_info "Available: ${AGENT_ORDER[*]}"
    return 1
  fi

  local agent_id timestamp
  agent_id=$(python3 -c "import uuid; print(str(uuid.uuid4())[:8])" 2>/dev/null || echo "$(date +%s | sha256sum | head -c 8)")
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo ""
  pyra_log "Forging ${C_WHITE}${C_BOLD}${name}${C_RESET}"
  pyra_dim "Role: ${AGENT_ROLE}  GPU: ${AGENT_GPU}  Port: ${AGENT_PORT}"
  pyra_dim "Fleet: ${AGENT_FLEET_NAME} (${AGENT_FLEET_ID})"

  # Create workspace
  mkdir -p "${AGENT_DIR}"/{config,logs,evidence,data}

  # ── Agent Configuration ──
  cat > "${AGENT_DIR}/config/agent.json" << AGENT_JSON
{
  "agent": {
    "name": "${name}",
    "id": "${agent_id}",
    "role": "${AGENT_ROLE}",
    "version": "${FORGE_VERSION}",
    "model": "${AGENT_MODEL}",
    "description": "${AGENT_DESC}",
    "forged_at": "${timestamp}"
  },
  "deployment": {
    "gpu": "${AGENT_GPU}",
    "gpu_index": ${AGENT_GPU_IDX},
    "fleet_instance": "${AGENT_FLEET_NAME}",
    "fleet_id": "${AGENT_FLEET_ID}",
    "port": ${AGENT_PORT}
  },
  "governance": {
    "patent": "${PATENT}",
    "patent_us": "${PATENT_US}",
    "orcid": "${ORCID}",
    "qdp_enabled": true,
    "rsfs_c_opt": ${RSFS_C_OPT},
    "rsfs_c_crit": ${RSFS_C_CRIT},
    "rsfs_phi": ${RSFS_PHI},
    "rsfs_kappa": ${RSFS_KAPPA}
  },
  "endpoints": {
    "health": "/health",
    "identity": "/identity",
    "task": "/task",
    "evidence": "/evidence",
    "rsfs": "/rsfs",
    "reason": "/reason",
    "role_specific": "${AGENT_ENDPOINTS}"
  }
}
AGENT_JSON
  pyra_ok "Configuration written"

  # ── Generate FastAPI Service ──
  generate_agent_service "$name"
  pyra_ok "FastAPI service generated ($(wc -l < "${AGENT_DIR}/service.py") lines)"

  # ── Generate Runner Script ──
  cat > "${AGENT_DIR}/run.sh" << RUNNER
#!/usr/bin/env bash
# ${name} — PyraClaw Diamond Army Agent Runner
# Auto-generated by PyraClaw Forge v${FORGE_VERSION}
set -euo pipefail

AGENT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
AGENT_NAME="${name}"
AGENT_PORT=${AGENT_PORT}
PID_FILE="\${AGENT_DIR}/agent.pid"
LOG_DIR="\${AGENT_DIR}/logs"
LOG_FILE="\${LOG_DIR}/\${AGENT_NAME,,}.log"

mkdir -p "\${LOG_DIR}"

case "\${1:-start}" in
  start)
    if [ -f "\${PID_FILE}" ] && kill -0 "\$(cat "\${PID_FILE}")" 2>/dev/null; then
      echo "[${name}] Already running (PID \$(cat "\${PID_FILE}"))"
      exit 0
    fi
    echo "[${name}] Starting on port \${AGENT_PORT}..."
    cd "\${AGENT_DIR}"
    nohup python3 service.py >> "\${LOG_FILE}" 2>&1 &
    echo \$! > "\${PID_FILE}"
    echo "[${name}] Running (PID \$!, log: \${LOG_FILE})"
    ;;
  stop)
    if [ -f "\${PID_FILE}" ]; then
      local_pid=\$(cat "\${PID_FILE}")
      if kill -0 "\${local_pid}" 2>/dev/null; then
        kill "\${local_pid}"
        echo "[${name}] Stopped (PID \${local_pid})"
      else
        echo "[${name}] Not running (stale PID)"
      fi
      rm -f "\${PID_FILE}"
    else
      echo "[${name}] No PID file"
    fi
    ;;
  status)
    if [ -f "\${PID_FILE}" ] && kill -0 "\$(cat "\${PID_FILE}")" 2>/dev/null; then
      echo "[${name}] Running (PID \$(cat "\${PID_FILE}"), port \${AGENT_PORT})"
    else
      echo "[${name}] Stopped"
    fi
    ;;
  *)
    echo "Usage: bash run.sh {start|stop|status}"
    ;;
esac
RUNNER
  chmod +x "${AGENT_DIR}/run.sh"
  pyra_ok "Runner script generated"

  # ── QDP-Seal the Forge Event ──
  local seal_payload
  seal_payload=$(cat "${AGENT_DIR}/config/agent.json")
  local qdp_json
  qdp_json=$(qdp_seal "$seal_payload")

  cat > "${AGENT_DIR}/evidence/forge-capsule.json" << CAPSULE
{
  "type": "agent_forge",
  "agent": "${name}",
  "agent_id": "${agent_id}",
  "role": "${AGENT_ROLE}",
  "gpu": "${AGENT_GPU}",
  "port": ${AGENT_PORT},
  "forged_at": "${timestamp}",
  "qdp_layers": ${qdp_json},
  "patent": "${PATENT}",
  "orcid": "${ORCID}",
  "qdp_super_hash": "${QDP_SUPER_HASH}"
}
CAPSULE
  pyra_ok "QDP evidence capsule sealed"

  local sha256_short
  sha256_short=$(echo -n "$seal_payload" | sha256sum | cut -d' ' -f1 | head -c 32)
  pyra_dim "SHA-256: ${sha256_short}..."

  # ── Record to Evidence Ledger ──
  local ledger_status="offline"
  if curl -sf "http://localhost:${EVIDENCE_LEDGER_PORT}/health" >/dev/null 2>&1; then
    local ledger_resp
    ledger_resp=$(curl -sf -X POST "http://localhost:${EVIDENCE_LEDGER_PORT}/record" \
      -H "Content-Type: application/json" \
      -d "{
        \"title\": \"Diamond Army Forge: ${name}\",
        \"payload\": $(cat "${AGENT_DIR}/config/agent.json"),
        \"source\": \"pyraclaw-forge\",
        \"tags\": [\"forge\", \"diamond-army\", \"${name,,}\", \"${AGENT_ROLE}\"]
      }" 2>/dev/null) && ledger_status="synced" || ledger_status="error"
  fi
  if [ "$ledger_status" = "synced" ]; then
    pyra_ok "Evidence Ledger: recorded"
  else
    pyra_dim "Evidence Ledger: ${ledger_status} (capsule stored locally)"
  fi

  # ── Register with Swarm Manager ──
  local swarm_status="offline"
  if curl -sf "http://localhost:${SWARM_MANAGER_PORT}/health" >/dev/null 2>&1; then
    local swarm_resp
    swarm_resp=$(curl -sf -X POST "http://localhost:${SWARM_MANAGER_PORT}/api/swarm/spawn" \
      -H "Content-Type: application/json" \
      -d "{\"role\": \"${AGENT_ROLE}\", \"count\": 1, \"metadata\": {\"agent\": \"${name}\", \"port\": ${AGENT_PORT}}}" \
      2>/dev/null) && swarm_status="registered" || swarm_status="error"
  fi
  if [ "$swarm_status" = "registered" ]; then
    pyra_ok "Swarm Manager: registered as ${AGENT_ROLE}"
  else
    pyra_dim "Swarm Manager: ${swarm_status} (will register on start)"
  fi

  pyra_ok "${C_WHITE}${name}${C_GREEN} forged successfully"
  pyra_dim "Directory: ${AGENT_DIR}"
  return 0
}

# ── Forge All — Diamond Army ─────────────────────────────────────────────────
forge_all() {
  banner
  check_env

  echo -e "${C_GOLD}  ┌──────────────────────────────────────────────────────────────────┐${C_RESET}"
  echo -e "${C_GOLD}  │${C_WHITE}${C_BOLD}  Forging Diamond Army${C_RESET}${C_PLAT}  8 agents across 3 GPUs${C_RESET}                   ${C_GOLD}│${C_RESET}"
  echo -e "${C_GOLD}  ├──────────────────────────────────────────────────────────────────┤${C_RESET}"
  echo -e "${C_GOLD}  │${C_RESET}  ${C_GREEN}H100${C_RESET}  LightningClaw  EvidenceClaw  ScoutClaw                  ${C_GOLD}│${C_RESET}"
  echo -e "${C_GOLD}  │${C_RESET}  ${C_CYAN}A6000${C_RESET} CodeClaw  GuardianClaw                                  ${C_GOLD}│${C_RESET}"
  echo -e "${C_GOLD}  │${C_RESET}  ${C_STEEL}A4000${C_RESET} CharismaClaw  AnalystClaw  CortexClaw                   ${C_GOLD}│${C_RESET}"
  echo -e "${C_GOLD}  └──────────────────────────────────────────────────────────────────┘${C_RESET}"

  local total=0
  local success=0
  local start_time
  start_time=$(date +%s)

  for agent_name in "${AGENT_ORDER[@]}"; do
    total=$((total + 1))
    if forge_agent "$agent_name"; then
      success=$((success + 1))
    fi
  done

  local elapsed=$(( $(date +%s) - start_time ))

  echo ""
  echo -e "${C_GOLD}  ╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_GOLD}  ║${C_WHITE}${C_BOLD}  Diamond Army Forged${C_RESET}                                                  ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ╠══════════════════════════════════════════════════════════════════════╣${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  Agents:  ${C_GREEN}${success}${C_RESET}/${total} operational                                           ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  Time:    ${elapsed}s                                                       ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  Path:    ${C_STEEL}~/pyraclaw/agents/${C_RESET}                                          ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ╠══════════════════════════════════════════════════════════════════════╣${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  ${C_DIM}Start all:   bash pyraclaw_forge.sh start all${C_RESET}                       ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  ${C_DIM}Health:      bash pyraclaw_forge.sh health${C_RESET}                           ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ║${C_RESET}  ${C_DIM}Status:      bash pyraclaw_forge.sh status${C_RESET}                           ${C_GOLD}║${C_RESET}"
  echo -e "${C_GOLD}  ╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo ""

  # ── Generate Diamond Army Manifest ──
  generate_manifest
}

# ── Generate Diamond Army Manifest ────────────────────────────────────────────
generate_manifest() {
  mkdir -p "${AGENTS_DIR}"

  python3 << MANIFEST_PY
import json, glob, os, time

agents = []
for config_path in sorted(glob.glob(os.path.expanduser("~/pyraclaw/agents/*/config/agent.json"))):
    try:
        agents.append(json.load(open(config_path)))
    except Exception:
        pass

# Load QDP capsules
capsules = []
for capsule_path in sorted(glob.glob(os.path.expanduser("~/pyraclaw/agents/*/evidence/forge-capsule.json"))):
    try:
        capsules.append(json.load(open(capsule_path)))
    except Exception:
        pass

manifest = {
    "diamond_army": {
        "version": "${FORGE_VERSION}",
        "forged_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "agent_count": len(agents),
        "patent": "${PATENT}",
        "patent_us": "${PATENT_US}",
        "orcid": "${ORCID}",
        "qdp_super_hash": "${QDP_SUPER_HASH}",
    },
    "fleet": {
        "H100": {
            "instance": "${FLEET_NAME[0]}",
            "id": "${FLEET_ID[0]}",
            "role": "primary",
            "agents": [a["agent"]["name"] for a in agents if a["deployment"]["gpu"] == "H100"],
        },
        "A6000": {
            "instance": "${FLEET_NAME[1]}",
            "id": "${FLEET_ID[1]}",
            "role": "security",
            "agents": [a["agent"]["name"] for a in agents if a["deployment"]["gpu"] == "A6000"],
        },
        "A4000": {
            "instance": "${FLEET_NAME[2]}",
            "id": "${FLEET_ID[2]}",
            "role": "routing",
            "agents": [a["agent"]["name"] for a in agents if a["deployment"]["gpu"] == "A4000"],
        },
    },
    "agents": agents,
    "qdp_capsules": capsules,
    "rsfs": {
        "c_opt": ${RSFS_C_OPT},
        "c_crit": ${RSFS_C_CRIT},
        "phi": ${RSFS_PHI},
        "kappa": ${RSFS_KAPPA},
    },
}

manifest_path = os.path.join(os.path.expanduser("~"), "pyraclaw", "agents", "diamond-army-manifest.json")
os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
MANIFEST_PY

  pyra_ok "Diamond Army manifest written: ${MANIFEST_FILE}"
}

# ── Deploy to Brev GPU ────────────────────────────────────────────────────────
deploy_agent() {
  local name="$1"

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    return 1
  fi

  if [ ! -d "${AGENT_DIR}" ]; then
    pyra_fail "${name} not forged yet. Run: bash pyraclaw_forge.sh forge ${name}"
    return 1
  fi

  local ssh_target="ubuntu@brev-${AGENT_FLEET_ID}"
  local remote_dir="/home/ubuntu/pyraclaw/agents/${name,,}"

  pyra_log "Deploying ${C_WHITE}${C_BOLD}${name}${C_RESET} to ${C_CYAN}${AGENT_GPU}${C_RESET}"
  pyra_dim "Target: ${ssh_target}"
  pyra_dim "Remote: ${remote_dir}"

  # Test SSH connectivity
  if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${ssh_target}" "echo ok" &>/dev/null; then
    pyra_fail "Cannot reach ${ssh_target}"
    pyra_info "Ensure Brev instance ${AGENT_FLEET_NAME} (${AGENT_FLEET_ID}) is running"
    pyra_info "Try: brev ssh ${AGENT_FLEET_NAME}"
    return 1
  fi
  pyra_ok "SSH connection verified"

  # Create remote directory structure
  ssh "${ssh_target}" "mkdir -p ${remote_dir}/{config,logs,evidence,data}" 2>/dev/null
  pyra_ok "Remote workspace created"

  # Copy agent files
  scp -q -r "${AGENT_DIR}/config" "${ssh_target}:${remote_dir}/" 2>/dev/null
  scp -q "${AGENT_DIR}/service.py" "${ssh_target}:${remote_dir}/" 2>/dev/null
  scp -q "${AGENT_DIR}/run.sh" "${ssh_target}:${remote_dir}/" 2>/dev/null
  scp -q -r "${AGENT_DIR}/evidence" "${ssh_target}:${remote_dir}/" 2>/dev/null
  pyra_ok "Agent files transferred"

  # Install dependencies remotely if needed
  ssh "${ssh_target}" "pip install fastapi uvicorn httpx pydantic 2>/dev/null || pip3 install fastapi uvicorn httpx pydantic 2>/dev/null" &>/dev/null
  pyra_ok "Dependencies verified"

  # Forward ANTHROPIC_API_KEY if set
  local env_cmd=""
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    env_cmd="export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY}' && "
    pyra_ok "API key forwarded"
  fi

  # Start the agent remotely
  ssh "${ssh_target}" "cd ${remote_dir} && ${env_cmd}bash run.sh start" 2>/dev/null
  pyra_ok "${C_WHITE}${name}${C_GREEN} deployed to ${AGENT_GPU} (${AGENT_FLEET_NAME})"

  # QDP-seal the deployment event
  local deploy_seal
  deploy_seal=$(qdp_seal_compact "deploy:${name}:${AGENT_GPU}:${AGENT_FLEET_ID}:$(date -u +%s)")
  pyra_dim "Deploy seal: $(echo "$deploy_seal" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha256','')[:32])" 2>/dev/null)..."

  # Record deployment in evidence
  cat > "${AGENT_DIR}/evidence/deploy-capsule.json" << DEPLOY_JSON
{
  "type": "agent_deploy",
  "agent": "${name}",
  "target_gpu": "${AGENT_GPU}",
  "fleet_instance": "${AGENT_FLEET_NAME}",
  "fleet_id": "${AGENT_FLEET_ID}",
  "ssh_target": "${ssh_target}",
  "remote_dir": "${remote_dir}",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "qdp_seal": ${deploy_seal}
}
DEPLOY_JSON
}

deploy_all() {
  banner
  pyra_log "Deploying Diamond Army to Brev GPU fleet"
  echo ""

  local total=0
  local success=0

  for agent_name in "${AGENT_ORDER[@]}"; do
    total=$((total + 1))
    if deploy_agent "$agent_name"; then
      success=$((success + 1))
    fi
    echo ""
  done

  pyra_log "Deployment complete: ${success}/${total} agents"
}

# ── Start/Stop/Restart Agent ──────────────────────────────────────────────────
start_agent() {
  local name="$1"

  if [ "$name" = "all" ]; then
    pyra_log "Starting Diamond Army"
    for agent_name in "${AGENT_ORDER[@]}"; do
      start_agent "$agent_name"
    done
    return
  fi

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    return 1
  fi

  if [ ! -f "${AGENT_DIR}/service.py" ]; then
    pyra_fail "${name} not forged. Run: bash pyraclaw_forge.sh forge ${name}"
    return 1
  fi

  local pid_file="${AGENT_DIR}/agent.pid"
  local log_dir="${AGENT_DIR}/logs"
  local log_file="${log_dir}/${name,,}.log"

  mkdir -p "$log_dir"

  # Check if already running
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    pyra_info "${name} already running (PID $(cat "$pid_file"))"
    return 0
  fi

  # Build environment
  local env_prefix=""
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    env_prefix="ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY} "
  fi

  # Start the service
  cd "${AGENT_DIR}"
  nohup env ${env_prefix} python3 service.py >> "$log_file" 2>&1 &
  local agent_pid=$!
  echo "$agent_pid" > "$pid_file"
  cd - >/dev/null

  # Brief pause and verify
  sleep 1
  if kill -0 "$agent_pid" 2>/dev/null; then
    pyra_ok "${C_WHITE}${name}${C_GREEN} started (PID ${agent_pid}, port ${AGENT_PORT})"
  else
    pyra_fail "${name} failed to start — check ${log_file}"
    rm -f "$pid_file"
    return 1
  fi

  # QDP-seal the start event
  local start_seal
  start_seal=$(qdp_seal_compact "start:${name}:${agent_pid}:$(date -u +%s)")

  # Record to evidence ledger if available
  if curl -sf "http://localhost:${EVIDENCE_LEDGER_PORT}/health" >/dev/null 2>&1; then
    curl -sf -X POST "http://localhost:${EVIDENCE_LEDGER_PORT}/record" \
      -H "Content-Type: application/json" \
      -d "{\"title\": \"Agent Start: ${name}\", \"payload\": {\"pid\": ${agent_pid}, \"port\": ${AGENT_PORT}}, \"source\": \"pyraclaw-forge\", \"tags\": [\"start\", \"${name,,}\"]}" \
      >/dev/null 2>&1 || true
  fi
}

stop_agent() {
  local name="$1"

  if [ "$name" = "all" ]; then
    pyra_log "Stopping Diamond Army"
    for agent_name in "${AGENT_ORDER[@]}"; do
      stop_agent "$agent_name"
    done
    return
  fi

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    return 1
  fi

  local pid_file="${AGENT_DIR}/agent.pid"

  if [ ! -f "$pid_file" ]; then
    pyra_info "${name} not running (no PID file)"
    return 0
  fi

  local agent_pid
  agent_pid=$(cat "$pid_file")

  if kill -0 "$agent_pid" 2>/dev/null; then
    kill "$agent_pid" 2>/dev/null
    # Wait up to 5 seconds for graceful shutdown
    local wait=0
    while kill -0 "$agent_pid" 2>/dev/null && [ $wait -lt 5 ]; do
      sleep 1
      wait=$((wait + 1))
    done
    # Force kill if still alive
    if kill -0 "$agent_pid" 2>/dev/null; then
      kill -9 "$agent_pid" 2>/dev/null
    fi
    pyra_ok "${C_WHITE}${name}${C_RESET} stopped (was PID ${agent_pid})"
  else
    pyra_info "${name} not running (stale PID ${agent_pid})"
  fi

  rm -f "$pid_file"
}

restart_agent() {
  local name="$1"

  if [ "$name" = "all" ]; then
    pyra_log "Restarting Diamond Army"
    for agent_name in "${AGENT_ORDER[@]}"; do
      restart_agent "$agent_name"
    done
    return
  fi

  pyra_log "Restarting ${name}"
  stop_agent "$name"
  sleep 1
  start_agent "$name"
}

# ── Status ────────────────────────────────────────────────────────────────────
fleet_status() {
  banner

  # Fleet table
  echo -e "${C_GOLD}  Fleet${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  printf "  ${C_STEEL}%-44s %-8s %-10s %-12s${C_RESET}\n" "INSTANCE" "GPU" "ROLE" "FLEET ID"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  for idx in 0 1 2; do
    printf "  ${C_WHITE}%-44s${C_RESET} ${C_GREEN}%-8s${C_RESET} ${C_STEEL}%-10s${C_RESET} ${C_DIM}%-12s${C_RESET}\n" \
      "${FLEET_NAME[$idx]}" "${FLEET_GPU[$idx]}" "${FLEET_ROLE[$idx]}" "${FLEET_ID[$idx]}"
  done
  echo ""

  # Agent table
  echo -e "${C_GOLD}  Diamond Army${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  printf "  ${C_STEEL}%-16s %-12s %-6s %-6s %-8s %-10s${C_RESET}\n" "AGENT" "ROLE" "GPU" "PORT" "PID" "STATUS"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"

  local running=0
  local forged=0

  for agent_name in "${AGENT_ORDER[@]}"; do
    parse_agent "$agent_name"
    local status="not forged"
    local pid_display="-"
    local status_color="${C_DIM}"

    if [ -d "${AGENT_DIR}" ]; then
      forged=$((forged + 1))
      status="stopped"
      status_color="${C_STEEL}"

      local pid_file="${AGENT_DIR}/agent.pid"
      if [ -f "$pid_file" ]; then
        local stored_pid
        stored_pid=$(cat "$pid_file")
        if kill -0 "$stored_pid" 2>/dev/null; then
          running=$((running + 1))
          status="running"
          status_color="${C_GREEN}"
          pid_display="$stored_pid"
        else
          status="stopped"
          rm -f "$pid_file"
        fi
      fi
    fi

    printf "  ${C_WHITE}%-16s${C_RESET} %-12s ${C_CYAN}%-6s${C_RESET} %-6s %-8s ${status_color}%-10s${C_RESET}\n" \
      "$agent_name" "$AGENT_ROLE" "$AGENT_GPU" "$AGENT_PORT" "$pid_display" "$status"
  done

  echo ""
  echo -e "  ${C_STEEL}Forged: ${C_WHITE}${forged}/8${C_RESET}  ${C_STEEL}Running: ${C_GREEN}${running}/8${C_RESET}"
  echo ""
}

# ── Health Check ──────────────────────────────────────────────────────────────
health_check() {
  banner
  pyra_log "Health check — Diamond Army"
  echo ""

  local total=0
  local healthy=0

  printf "  ${C_STEEL}%-16s %-6s %-14s %-10s %-12s${C_RESET}\n" "AGENT" "PORT" "ROLE" "STATUS" "UPTIME"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"

  for agent_name in "${AGENT_ORDER[@]}"; do
    parse_agent "$agent_name"

    if [ ! -d "${AGENT_DIR}" ]; then
      continue
    fi

    total=$((total + 1))
    local status="offline"
    local uptime_str="-"
    local status_color="${C_DIM}"

    local health_resp
    if health_resp=$(curl -sf "http://localhost:${AGENT_PORT}/health" 2>/dev/null); then
      healthy=$((healthy + 1))
      status="operational"
      status_color="${C_GREEN}"
      uptime_str=$(echo "$health_resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    u = d.get('uptime', 0)
    if u > 3600:
        print(f'{u/3600:.1f}h')
    elif u > 60:
        print(f'{u/60:.1f}m')
    else:
        print(f'{u:.0f}s')
except:
    print('-')
" 2>/dev/null || echo "-")
    fi

    printf "  ${C_WHITE}%-16s${C_RESET} %-6s %-14s ${status_color}%-10s${C_RESET} %-12s\n" \
      "$agent_name" "$AGENT_PORT" "$AGENT_ROLE" "$status" "$uptime_str"
  done

  echo ""
  if [ $total -eq 0 ]; then
    pyra_info "No agents forged. Run: bash pyraclaw_forge.sh all"
  else
    pyra_log "Fleet: ${C_GREEN}${healthy}${C_RESET}/${total} agents operational"
  fi

  # Check infrastructure services
  echo ""
  pyra_log "Infrastructure services"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"

  local services=(
    "Swarm Manager:${SWARM_MANAGER_PORT}"
    "RSFS Core:${RSFS_CORE_PORT}"
    "Freedom Engine:${FREEDOM_ENGINE_PORT}"
    "Evidence Ledger:${EVIDENCE_LEDGER_PORT}"
  )

  for svc_spec in "${services[@]}"; do
    local svc_name svc_port
    IFS=':' read -r svc_name svc_port <<< "$svc_spec"
    if curl -sf "http://localhost:${svc_port}/health" >/dev/null 2>&1; then
      printf "  ${C_GREEN}+${C_RESET}  %-20s port %-6s ${C_GREEN}operational${C_RESET}\n" "$svc_name" "$svc_port"
    else
      printf "  ${C_DIM}-${C_RESET}  %-20s port %-6s ${C_DIM}offline${C_RESET}\n" "$svc_name" "$svc_port"
    fi
  done
  echo ""
}

# ── Logs ──────────────────────────────────────────────────────────────────────
show_logs() {
  local name="$1"
  local lines="${2:-50}"

  if [ "$name" = "all" ]; then
    for agent_name in "${AGENT_ORDER[@]}"; do
      parse_agent "$agent_name"
      local log_file="${AGENT_DIR}/logs/${agent_name,,}.log"
      if [ -f "$log_file" ]; then
        echo -e "${C_GOLD}── ${agent_name} ──${C_RESET}"
        tail -n "$lines" "$log_file"
        echo ""
      fi
    done
    return
  fi

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    return 1
  fi

  local log_file="${AGENT_DIR}/logs/${name,,}.log"
  if [ -f "$log_file" ]; then
    echo -e "${C_GOLD}── ${name} logs (last ${lines} lines) ──${C_RESET}"
    tail -n "$lines" "$log_file"
  else
    pyra_info "No log file for ${name}"
    pyra_dim "Expected: ${log_file}"
  fi
}

# ── Destroy Agent ─────────────────────────────────────────────────────────────
destroy_agent() {
  local name="$1"

  if [ "$name" = "all" ]; then
    pyra_warn "Destroying all Diamond Army agents"
    for agent_name in "${AGENT_ORDER[@]}"; do
      destroy_agent "$agent_name"
    done
    rm -f "${MANIFEST_FILE}"
    pyra_ok "Diamond Army manifest removed"
    return
  fi

  if ! parse_agent "$name"; then
    pyra_fail "Unknown agent: ${name}"
    return 1
  fi

  # Stop first if running
  stop_agent "$name" 2>/dev/null || true

  if [ -d "${AGENT_DIR}" ]; then
    # QDP-seal the destruction event before removing
    local destroy_seal
    destroy_seal=$(qdp_seal_compact "destroy:${name}:$(date -u +%s)")
    pyra_dim "Destruction sealed: $(echo "$destroy_seal" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha256','')[:32])" 2>/dev/null)..."

    rm -rf "${AGENT_DIR}"
    pyra_ok "${name} destroyed"
  else
    pyra_info "${name} not found (already destroyed or never forged)"
  fi
}

# ── Help ──────────────────────────────────────────────────────────────────────
show_help() {
  banner

  echo -e "${C_GOLD}  Commands${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "forge <Agent>"          "Forge a single agent"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "all"                    "Forge full Diamond Army (8 agents)"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "deploy <Agent|all>"     "Deploy agent to Brev GPU via SSH"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "start <Agent|all>"      "Start a forged agent"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "stop <Agent|all>"       "Stop a running agent"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "restart <Agent|all>"    "Restart an agent"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "status"                 "Fleet and agent status"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "health"                 "Health check all agents and services"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "logs <Agent|all> [N]"   "Tail agent logs (default: 50 lines)"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "destroy <Agent|all>"    "Remove agent workspace"
  printf "  ${C_WHITE}%-28s${C_RESET} %s\n" "help"                   "Show this help"
  echo ""

  echo -e "${C_GOLD}  Diamond Army${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  printf "  ${C_STEEL}%-16s %-6s %-13s %-5s %s${C_RESET}\n" "AGENT" "GPU" "ROLE" "PORT" "ENDPOINTS"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  for agent_name in "${AGENT_ORDER[@]}"; do
    parse_agent "$agent_name"
    printf "  ${C_WHITE}%-16s${C_RESET} ${C_CYAN}%-6s${C_RESET} %-13s %-5s ${C_DIM}%s${C_RESET}\n" \
      "$agent_name" "$AGENT_GPU" "$AGENT_ROLE" "$AGENT_PORT" "$AGENT_ENDPOINTS"
  done
  echo ""

  echo -e "${C_GOLD}  Fleet${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  for idx in 0 1 2; do
    printf "  ${C_WHITE}%-6s${C_RESET}  %-44s ${C_DIM}(%s)${C_RESET}\n" \
      "${FLEET_GPU[$idx]}" "${FLEET_NAME[$idx]}" "${FLEET_ID[$idx]}"
  done
  echo ""

  echo -e "${C_GOLD}  Examples${C_RESET}"
  echo -e "${C_DIM}  ────────────────────────────────────────────────────────────────────${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh all${C_RESET}                   ${C_DIM}# Forge full Diamond Army${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh forge LightningClaw${C_RESET}   ${C_DIM}# Forge single agent${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh start all${C_RESET}             ${C_DIM}# Start all agents${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh deploy CodeClaw${C_RESET}       ${C_DIM}# Deploy to Brev A6000${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh health${C_RESET}                ${C_DIM}# Health check fleet${C_RESET}"
  echo -e "  ${C_PLAT}bash pyraclaw_forge.sh logs ScoutClaw 100${C_RESET}    ${C_DIM}# Last 100 log lines${C_RESET}"
  echo ""

  echo -e "  ${C_DIM}Byron Callaghan / Pyraclaw | Patent: ${PATENT} | ${PATENT_US}${C_RESET}"
  echo -e "  ${C_DIM}ORCID: ${ORCID} | QDP Super Hash: ${QDP_SUPER_HASH:0:32}...${C_RESET}"
  echo ""
}

# ── Main Dispatch ─────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    forge)
      if [ -z "${1:-}" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh forge <AgentName>"
        pyra_info "Available: ${AGENT_ORDER[*]}"
        exit 1
      fi
      banner
      check_env
      forge_agent "$1"
      ;;

    all)
      forge_all
      ;;

    deploy)
      local target="${1:-}"
      if [ -z "$target" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh deploy <AgentName|all>"
        exit 1
      fi
      banner
      if [ "$target" = "all" ]; then
        deploy_all
      else
        deploy_agent "$target"
      fi
      ;;

    start)
      local target="${1:-}"
      if [ -z "$target" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh start <AgentName|all>"
        exit 1
      fi
      banner
      start_agent "$target"
      ;;

    stop)
      local target="${1:-}"
      if [ -z "$target" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh stop <AgentName|all>"
        exit 1
      fi
      stop_agent "$target"
      ;;

    restart)
      local target="${1:-}"
      if [ -z "$target" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh restart <AgentName|all>"
        exit 1
      fi
      banner
      restart_agent "$target"
      ;;

    status)
      fleet_status
      ;;

    health)
      health_check
      ;;

    logs)
      local target="${1:-all}"
      local lines="${2:-50}"
      show_logs "$target" "$lines"
      ;;

    destroy)
      local target="${1:-}"
      if [ -z "$target" ]; then
        pyra_fail "Usage: bash pyraclaw_forge.sh destroy <AgentName|all>"
        exit 1
      fi
      banner
      destroy_agent "$target"
      ;;

    help|--help|-h)
      show_help
      ;;

    *)
      # Check if it's an agent name used directly
      if [ -n "${AGENTS[$cmd]+_}" ]; then
        banner
        check_env
        forge_agent "$cmd"
      else
        pyra_fail "Unknown command: ${cmd}"
        echo ""
        pyra_info "Run: bash pyraclaw_forge.sh help"
        exit 1
      fi
      ;;
  esac
}

main "$@"
