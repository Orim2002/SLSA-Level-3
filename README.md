# SLSA Level 3 Supply Chain Security Pipeline

A production-grade software supply chain security pipeline built on SLSA Level 3 compliance, featuring signed commits, vulnerability scanning, image signing, provenance generation, and GitOps-based deployment with policy enforcement.

---

## Architecture

```
Developer Machine
└── GPG-signed git commit
        │
        ▼
GitHub Actions CI/CD Pipeline
├── 1. Verify commit GPG signature
├── 2. Build Docker image → push to GHCR (staging)
├── 3. Generate SBOM (Syft / CycloneDX)
├── 4. Scan for vulnerabilities (Grype) — fail on HIGH
├── 5. Push to DockerHub (only after scan passes)
├── 6. Sign image with Cosign (by digest)
├── 7. Generate SLSA provenance (slsa-github-generator)
└── 8. Update Helm chart with new image tag
        │
        ▼
ArgoCD (GitOps)
└── Detects Helm chart change → triggers deployment
        │
        ▼
Kubernetes Cluster
├── Kyverno (admission controller)
│   └── Blocks any unsigned image from running
└── Flask app deployed ✅
```

---

## Security Features

### Signed Commits (GPG)
Every commit is signed with a GPG key (ed25519, Curve 25519). The CI pipeline verifies the signature before building, ensuring no unsigned code can enter the pipeline.

### Staged Build (GHCR → DockerHub)
Images are first pushed to GitHub Container Registry as a staging environment. Vulnerability scanning runs against the staged image. Only after passing the scan is the image promoted to DockerHub.

### SBOM Generation (Syft)
A Software Bill of Materials is generated in CycloneDX JSON format for every build. The SBOM is uploaded as a pipeline artifact, giving full visibility into every dependency in the image.

### Vulnerability Scanning (Grype)
Grype scans the SBOM and fails the pipeline on any HIGH or CRITICAL vulnerability. The scan report is uploaded as an artifact even on failure for investigation.

### Zero-CVE Base Image
The app uses `cgr.dev/chainguard/python` as its base image — a minimal, hardened image with zero known CVEs, compared to 7 HIGH CVEs in standard `python:3.12-slim`.

### Image Signing (Cosign)
After passing all scans, the image is signed using Cosign with a project-specific key pair. Signing is done **by digest** (not tag) to ensure immutability. The signature is published to the Sigstore transparency log (Rekor).

### SLSA Provenance (Level 3)
SLSA provenance is generated using the official `slsa-framework/slsa-github-generator`. This attestation cryptographically links the final image back to the exact source commit and build environment, satisfying SLSA Level 3 requirements.

### Kyverno Policy Enforcement
A `ClusterPolicy` enforces image integrity across the entire cluster using three layered rules:

- **Own images** — verified against the project's Cosign public key
- **ArgoCD images** — verified keyless via Sigstore against the official `argoproj/argo-cd` GitHub Actions identity
- **Kyverno images** — verified keyless via Sigstore against the official `kyverno/kyverno` GitHub Actions identity
- **Everything else** — denied outright (catch-all block rule)

No namespace is fully excluded from enforcement. `kube-system` is excluded only from the catch-all deny rule, as Kubernetes internals are not subject to Cosign signing.

### GitOps Deployment (ArgoCD)
The pipeline automatically updates the Helm chart's `values.yaml` with the new image tag after every successful build. ArgoCD detects the change and syncs the cluster — no manual deployments. The Helm chart repo is updated via an SSH deploy key (not a PAT), scoped to write access on that repo only.

---

## Pipeline Jobs

| Job | Description |
|-----|-------------|
| `docker-build-push-ghcr` | Verifies GPG signature, builds image, pushes to GHCR staging |
| `create-sbom` | Generates CycloneDX SBOM using Syft |
| `scan-image` | Scans SBOM with Grype, fails on HIGH vulnerabilities |
| `docker-build-push` | Promotes image from GHCR to DockerHub |
| `cosign-sign-image` | Signs image by digest using Cosign |
| `generate-provenance` | Generates SLSA Level 3 provenance attestation |
| `update-helmchart` | Updates Helm chart `values.yaml` with new image tag via SSH deploy key |

---

## Tools & Technologies

| Tool | Purpose |
|------|---------|
| GPG (ed25519) | Commit signing |
| GitHub Actions | CI/CD pipeline |
| Docker / GHCR | Image build & staging registry |
| DockerHub | Production image registry |
| [Syft](https://github.com/anchore/syft) | SBOM generation (CycloneDX) |
| [Grype](https://github.com/anchore/grype) | Vulnerability scanning |
| [Cosign](https://github.com/sigstore/cosign) | Image signing |
| [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator) | SLSA Level 3 provenance |
| [Kyverno](https://kyverno.io) | Kubernetes admission controller / policy enforcement |
| [ArgoCD](https://argoproj.github.io/cd/) | GitOps continuous deployment |
| [Helm](https://helm.sh) | Kubernetes package management |
| [kind](https://kind.sigs.k8s.io) | Local Kubernetes cluster |
| Chainguard Python | Zero-CVE base image |

---

## Repository Structure

```
SLSA-Level-3/                        # Main application repo
├── .github/
│   └── workflows/
│       └── pipeline.yml             # Full CI/CD pipeline
├── app.py                           # Flask application
├── Dockerfile                       # Container definition
└── cosign.pub                       # Cosign public key

SLSA-Level-3-Sampleapp-HelmChart/   # Helm chart repo (GitOps source)
├── Chart.yaml
├── values.yaml                      # Auto-updated by pipeline
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

---

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `GPG_PUBLIC_KEY` | GPG public key for commit verification |
| `DOCKERHUB_USERNAME` | DockerHub username |
| `DOCKERHUB_TOKEN` | DockerHub access token |
| `COSIGN_PRIVATE_KEY` | Cosign private key for image signing |
| `COSIGN_PASSWORD` | Cosign key passphrase |
| `COSIGN_PUBLIC_KEY` | Cosign public key |
| `HELM_DEPLOY_KEY` | SSH private key for updating the Helm chart repo |

---

## Kyverno Policy

The cluster enforces image integrity on every pod across all namespaces. Images are verified against their respective signing identities — unsigned or unknown images are rejected at admission time.

```yaml
# Example: blocked — unknown image
kubectl run unsigned --image=nginx:latest
# Error: admission webhook denied - only signed orima2002 images are allowed

# Example: allowed — signed image
kubectl run app --image=orima2002/sample-app:abc1234
# pod/app created
```

### Policy Rules Summary

| Rule | Matches | Verification Method |
|------|---------|-------------------|
| `verify-own-images` | `orima2002/*` images, all namespaces | Cosign key (`cosign.pub`) |
| `verify-argocd-images` | `quay.io/argoproj/*` in `argocd` namespace | Keyless via Sigstore |
| `verify-kyverno-images` | `ghcr.io/kyverno/*` in `kyverno` namespace | Keyless via Sigstore |
| `deny-unknown-images` | Any pod outside `kyverno`, `argocd`, `kube-system` | Deny if not `orima2002/*` |

---

## Verifying an Image

```bash
# Verify the Cosign signature
cosign verify \
  --key cosign.pub \
  orima2002/sample-app@sha256:<digest>

# Verify SLSA provenance
cosign verify-attestation \
  --key cosign.pub \
  --type slsaprovenance \
  orima2002/sample-app@sha256:<digest>
```

---

## SLSA Level 3 Compliance

| Requirement | Implementation |
|-------------|---------------|
| Signed build | GitHub Actions OIDC + slsa-github-generator |
| Isolated build | GitHub-hosted runners (ephemeral) |
| Auditable build | Full pipeline logs + provenance attestation |
| Signed provenance | Cosign + Sigstore transparency log |
| Source integrity | GPG-signed commits verified in CI |
| Dependency scanning | Syft SBOM + Grype vulnerability scan |

---

## Author

**Ori Maor** — [GitHub](https://github.com/Orim2002) | [Docker Hub](https://hub.docker.com/u/orima2002)