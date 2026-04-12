# PyraClaw v1.1.0-rc.1

**CI/CD Pipeline Suite with RSFS Quality Gates, QDP Evidence Sealing, and Diamond Army Agent Deployment System**

Byron Callaghan / Pyraclaw | Patent: PCT/EP2025/080977 | US 19/541,276

## Authors

| Name | ORCID | Role |
|------|-------|------|
| Byron Callaghan | [0009-0001-9561-5483](https://orcid.org/0009-0001-9561-5483) | Creator |
| PyraClaw iAiA | [0009-0003-9584-1741](https://orcid.org/0009-0003-9584-1741) | System Entity |

## DOI

**10.5281/zenodo.19482963**

## Contents

```
pyraclaw-v1.1.0-rc.1.zip     Source code archive
evidence/
  deposit-manifest.json       Zenodo deposit metadata with QDP seal
  diamond-army-h100-seals.json  8 agent QDP capsules (NVIDIA H100)
  diamond-army-dd7ai-seals.json 8 agent QDP capsules (Pyraclaw local)
  session-commits.json        Complete git commit ledger
```

## Deliverables

1. **CI/CD Pipelines** — GitHub Actions, Jenkins, GitLab CI with RSFS 8-dimension quality gates and QDP 4-layer evidence sealing
2. **Diamond Army Forge** — pyraclaw_forge.sh v2.0.0 (1,921 lines) deploying 8 FastAPI agents across Brev.dev GPU fleet
3. **Pyraclaw Integration** — PyraClaw bridge tool, agent profile, evidence logging extension

## Results

- 8/8 agents verified operational on NVIDIA H100 PCIe (81,559 MiB VRAM)
- 8/8 agents verified operational on local CPU
- QDP 4-layer evidence capsules sealed per forge event

## Scope Limitations

- Infrastructure services not deployed (Swarm Manager, Evidence Ledger, RSFS Core, Freedom Engine)
- NemoClaw GPU inference cluster not activated
- No end-to-end task execution; agents verified at health/identity level only

No overclaiming. Results-driven. Evidence-first.

## License

Apache-2.0
