# RHOAI Installation Notes

## 2026/04/26 - RHOAI 3.3.2 on OCP 4.20.18 (AWS)

### Cluster Info

- **OCP Version**: 4.20.18
- **Platform**: AWS (us-east-2)
- **Nodes**: 3 control-plane + 2 worker (no GPU nodes at bootstrap time)
- **Bootstrap overlay**: `rhoai-stable-3.x-aws-gpu`
- **ArgoCD Console**: `https://openshift-gitops-server-openshift-gitops.apps.<cluster-domain>`

### Installed Operators

| Operator | Version |
|----------|---------|
| RHOAI (rhods-operator) | 3.3.2 |
| Service Mesh 3 | 3.3.2 |
| Red Hat Connectivity Link | 1.3.2 |
| Authorino | 1.3.0 |
| Limitador | 1.3.0 |
| GPU Operator | 26.3.1 |
| NFD | 4.20 |
| Kueue | 1.3.1 |
| OpenShift Pipelines | 1.22.0 |
| OpenShift GitOps | 1.20.2 |
| Kiali | 2.22.2 |
| Custom Metrics Autoscaler | 2.18.1 |
| Leader Worker Set | 1.0.0 |

### Installation Steps

1. **Fork sync**: Synced fork with upstream `redhat-ai-services/ai-accelerator` (was 25 commits behind).
2. **Configure repoURL**: Updated `clusters/overlays/rhoai-stable-3.x-aws-gpu/kustomization.yaml` to point `repoURL` to the fork.
3. **Bootstrap**: Ran `./bootstrap.sh --bootstrap_dir=rhoai-stable-3.x-aws-gpu -f`.
4. **Approved InstallPlans**: Manually approved two pending InstallPlans (see Issue 1 below).
5. **Restored lost components**: Re-added custom components to `stable-3.x-nvidia-gpu` overlay (see Issue 2 below).

### Issues Encountered

#### Issue 1: InstallPlans stuck at RequiresApproval

**Symptom**: After bootstrap, `connectivity-link-operator` stayed `Missing` and `openshift-ai-operator` was `Degraded`. The `modelsAsService` component reported: `no matches for kind "AuthPolicy" in version "kuadrant.io/v1"`.

**Root cause**: The `servicemeshoperator3` Subscription had `installPlanApproval: Manual` on the cluster, even though the repo defines it as `Automatic`. This blocked the SM3 upgrade from v3.1.0 to v3.3.2, which in turn blocked the RHCL InstallPlan (RHCL depends on SM3 v3.3.2). The dependency chain was: SM3 upgrade blocked → RHCL can't install → AuthPolicy CRD missing → MaaS component fails.

Two InstallPlans needed approval:

- `install-9j7fq` — SM3 v3.3.2
- `install-xg8dh` — RHCL v1.3.2 + Authorino v1.3.0 + Limitador v1.3.0 + DNS Operator v1.3.0

**Fix**:

```bash
oc patch installplan <name> -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
```

**Will this recur?** Likely yes. This appears to be an OLM race condition during initial bootstrap — the SM3 operator installs at v3.1.0 first, then OLM detects v3.3.2 is available and creates an upgrade InstallPlan. During this process the approval policy can drift to `Manual`. Monitor InstallPlans after bootstrap:

```bash
oc get installplan -n openshift-operators -o custom-columns='NAME:.metadata.name,APPROVAL:.spec.approval,APPROVED:.spec.approved,PHASE:.status.phase'
```

If any show `RequiresApproval`, approve them with the patch command above.

#### Issue 2: Custom components lost after upstream merge

**Symptom**: `LlamaStackOperatorReady` showed `Removed` instead of `Managed`. Dashboard features (GenAI Studio, Model Catalog, etc.) were not configured. KServe NIM was not enabled. Custom model catalog was not deployed.

**Root cause**: Upstream commit `043517d` (Cleanup available channels) renamed the `fast-3.x-nvidia-gpu` overlay to `stable-3.x-nvidia-gpu`. Our custom commits (`5dcf5ec`, `5509755`) had added `components-kserve-nim`, `components-llamastack`, `dashboard-config`, and `custom-model-catalog` to the old `fast-3.x-nvidia-gpu` overlay. During `git merge upstream/main`, the rename and our modifications didn't merge cleanly — all four custom components were silently lost.

**Fix**: Manually re-added the four components to `instance-3.x/overlays/stable-3.x-nvidia-gpu/kustomization.yaml`:

```yaml
components:
  # ... existing components ...
  - ../../components/components-kserve-nim
  - ../../components/components-llamastack
  # ... existing components ...
  - ../../components/custom-model-catalog
  - ../../components/dashboard-config
  # ... existing components ...
```

The `custom-model-catalog` component (commits `be02b9f` + `5509755`) deploys a `model-catalog-sources` ConfigMap to `rhoai-model-registries` namespace, defining a custom model whitelist (`Custom Catalog - Demo` with label `Sheryl Selected`) containing Qwen3, Gemma, and other approved models.

**Will this recur?** Only when merging upstream changes. After merging, always diff the active overlay against your custom commits to verify no modifications were lost:

```bash
git diff upstream/main..HEAD -- components/operators/openshift-ai/instance-3.x/overlays/
```

### Pre-flight Checklist (for next time)

1. Sync fork with upstream: `git fetch upstream && git merge upstream/main`
2. Verify custom components survived the merge (see Issue 2)
3. Verify `repoURL` in the cluster overlay points to the fork
4. Ensure `oc`, `yq` (Go version) are installed; `kustomize` is auto-downloaded by the bootstrap script
5. Run bootstrap: `./bootstrap.sh --bootstrap_dir=rhoai-stable-3.x-aws-gpu -f`
6. After bootstrap, monitor InstallPlans and approve any stuck ones (see Issue 1)
7. Force ArgoCD refresh if needed: `oc annotate applications.argoproj.io <app-name> -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite`

---

## 2026/04/26 - Models-as-a-Service (MaaS) on RHOAI 3.3.2

> Source project: [opendatahub-io/models-as-a-service](https://github.com/opendatahub-io/models-as-a-service)
> Local path: `/Users/sherwang/Repo/models-as-a-service`

### What is MaaS

MaaS extends RHOAI with API key management, subscription-based access control, and token rate limiting for model inference endpoints. It adds a controller (`maas-controller`), an API service (`maas-api`), and custom CRDs (`Tenant`, `MaaSSubscription`, `MaaSModelRef`, `MaaSAuthPolicy`, `ExternalModel`) on top of KServe + Gateway API + Kuadrant/RHCL.

### Prerequisites (on top of RHOAI)

- RHOAI installed with `modelsAsService: Managed` in DSC
- RHCL / Kuadrant already deployed (provided by ai-accelerator)
- Gateway API v1, LWS, cert-manager already installed
- CLI tools: `oc`, `kubectl`, `jq`, `kustomize` 5.7.0+, `envsubst`, `gsed` (macOS)

### Installation Command

```bash
cd /Users/sherwang/Repo/models-as-a-service
./scripts/deploy.sh --operator-type rhoai
```

### Deployed Components

| Component | Namespace | Status |
|-----------|-----------|--------|
| maas-controller | redhat-ods-applications | Running |
| maas-api | redhat-ods-applications | Running |
| postgres (dev/ephemeral) | redhat-ods-applications | Running |
| maas-default-gateway | openshift-ingress | Programmed |
| Kuadrant | rh-connectivity-link | Created |
| default-tenant | models-as-a-service | Created |

### CRDs Created

`Tenant`, `MaaSSubscription`, `MaaSModelRef`, `MaaSAuthPolicy`, `ExternalModel`

### Issues Encountered

#### Issue 3: TooManyOperatorGroups — cert-manager and LWS

**Symptom**: `deploy.sh` timed out waiting for cert-manager and LWS CSV installation. CSV status showed `Failed` with reason `TooManyOperatorGroups`.

**Root cause**: The `scripts/data/cert-manager-subscription.yaml` and `scripts/data/lws-subscription.yaml` files contain hardcoded `OperatorGroup` resources. When ai-accelerator has already installed these operators (with differently-named OperatorGroups), `kubectl apply` creates a second OperatorGroup in the same namespace. OLM forbids multiple OperatorGroups per namespace, causing all CSVs in that namespace to fail.

**Fix**: Remove the `OperatorGroup` sections from both YAML files before running `deploy.sh`:

- `scripts/data/cert-manager-subscription.yaml` — remove the `kind: OperatorGroup` block
- `scripts/data/lws-subscription.yaml` — remove the `kind: OperatorGroup` block

If you already ran the script and hit this error, clean up:

```bash
oc delete operatorgroup cert-manager-operator -n cert-manager-operator
oc delete operatorgroup leader-worker-set -n openshift-lws-operator
```

**Will this recur?** Yes, every time you run `deploy.sh` on a cluster where ai-accelerator already installed cert-manager and LWS. Always remove the OperatorGroup blocks from the YAML files first.

#### Issue 4: DSC dashboard.managementState mismatch

**Symptom**: `deploy.sh` exited with error: `Existing DataScienceCluster 'default-dsc' does not meet MaaS requirements: .spec.components.dashboard.managementState: 'Managed' (expected 'Removed')`.

**Root cause**: The MaaS project's `scripts/data/datasciencecluster.yaml` defines `dashboard.managementState: Removed`, but our DSC (managed by ai-accelerator) sets it to `Managed`. The deploy script compares every field in its manifest against the live DSC and fails on any mismatch.

**Fix**: Edit `scripts/data/datasciencecluster.yaml` to match the cluster:

```yaml
    dashboard:
      managementState: Managed   # was: Removed
```

**Will this recur?** Yes. The MaaS project assumes a minimal DSC. When deploying on a cluster with a full RHOAI setup (ai-accelerator), this field will always conflict. Apply the same fix before running `deploy.sh`.

#### Issue 5: Kuadrant ready timeout and Authorino TLS (warnings, non-fatal)

**Symptom**: Two warnings during deployment:
1. `Kuadrant ready in rh-connectivity-link - Timeout after 60s`
2. `Authorino deployment not found after 300s` in `rh-connectivity-link` namespace

**Root cause**: The MaaS script creates a second RHCL instance in `rh-connectivity-link`, while ai-accelerator already installed RHCL/Authorino in `openshift-operators` / `kuadrant-system`. The script looks for Authorino in `rh-connectivity-link` but it's deployed elsewhere.

**Impact**: Non-fatal warnings. MaaS deployment completed successfully. AuthPolicy enforcement may need manual validation.

### Pre-flight Checklist (for MaaS on ai-accelerator clusters)

1. Sync fork with upstream before each install （要先做初步判断，再决定是否要接受上游更新！）: `cd /path/to/models-as-a-service && git fetch upstream && git merge upstream/main`
2. Ensure RHOAI is fully installed and DSC Ready (all ai-accelerator steps completed)
3. Install `kustomize` 5.7.0+ and `gsed` (macOS: `brew install gnu-sed`)
4. Edit `scripts/data/cert-manager-subscription.yaml` — remove OperatorGroup block (Issue 3)
5. Edit `scripts/data/lws-subscription.yaml` — remove OperatorGroup block (Issue 3)
6. Edit `scripts/data/datasciencecluster.yaml` — change `dashboard.managementState` to `Managed` (Issue 4)
7. Run: `cd /path/to/models-as-a-service && ./scripts/deploy.sh --operator-type rhoai`
8. Ignore Kuadrant/Authorino timeout warnings (Issue 5) — they are non-fatal
9. Note: PostgreSQL is ephemeral (dev only); for production use `--postgres-connection`
