# Deploy Qwen2.5-7B-Instruct on OpenShift AI

This guide shows how to deploy [Qwen2.5-7B-Instruct](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct) on OpenShift AI using KServe with vLLM runtime.

## Why Qwen2.5 instead of Qwen3.5?

| Model | Architecture | Red Hat vLLM (0.13.0) | Upstream vLLM |
|-------|--------------|----------------------|---------------|
| Qwen2.5 | `Qwen2ForCausalLM` | ✅ Supported | ✅ Supported |
| Qwen3.5 | `qwen3_5` (new) | ❌ Not yet | ✅ Supported |

Red Hat's vLLM image lags behind upstream for stability. When updated, Qwen3.5 will work.

## Prerequisites

1. OpenShift AI installed with KServe enabled
2. GPU node available (will auto-scale if configured)
3. No HF_TOKEN required (Apache-2.0 licensed model)

## Quick Deploy

```bash
# Apply the deployment
oc apply -f qwen25-7b-deployment.yaml

# Watch the deployment progress
oc get pods -n qwen-demo -w

# Check InferenceService status
oc get inferenceservice -n qwen-demo
```

### Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| GPU Node Provisioning | 3-5 min | If no GPU nodes available, autoscaler creates new ones |
| GPU Driver Install | 5-10 min | NVIDIA GPU Operator installs drivers on new nodes |
| Model Download | 3-5 min | Downloads ~15GB model from HuggingFace |
| Model Loading | 1-2 min | vLLM loads model into GPU memory |
| **Total (cold start)** | **12-22 min** | First deployment with no GPU nodes |
| **Total (warm start)** | **5-8 min** | GPU nodes already available |

## Testing the Model

Once deployed (READY=True), test with:

```bash
# Internal cluster test
oc run test-qwen --rm -i --restart=Never \
  --image=curlimages/curl:latest \
  -- curl -s http://qwen25-7b-predictor.qwen-demo.svc.cluster.local/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen25-7b", "messages": [{"role": "user", "content": "Hello!"}], "max_tokens": 50}'
```

Or via route:

```bash
# Get the route (if exposed)
ENDPOINT=$(oc get route -n qwen-demo -o jsonpath='{.items[0].spec.host}')

curl -X POST "https://${ENDPOINT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen25-7b",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "max_tokens": 100
  }'
```

## Using Gen AI Studio Playground

This deployment includes the `opendatahub.io/genai-asset: "true"` label, which makes the model available in the Gen AI Studio.

1. Go to **OpenShift AI Dashboard**
2. Navigate to **Gen AI Studio → AI Asset Endpoints**
3. Find `Qwen2.5-7B-Instruct` in the list
4. Click **"Add to playground"**
5. Start chatting with your model!

> **Note**: Requires `genAiStudio: true` in OdhDashboardConfig and `llamastackoperator.managementState: Managed` in DataScienceCluster.

## Model Specifications

| Spec | Value |
|------|-------|
| Model | Qwen/Qwen2.5-7B-Instruct |
| Parameters | 7B |
| License | Apache-2.0 |
| GPU Memory | ~16GB (BF16) |
| Max Context | 32K (limited to 8K in this config) |
| Recommended GPU | NVIDIA A10G (24GB) or better |

## Using a HuggingFace Token (for gated models)

If deploying a gated model, create a secret first:

```bash
oc create secret generic hf-token \
  --from-literal=HF_TOKEN=<your-hf-token> \
  -n qwen-demo
```

Then add to ServingRuntime env:

```yaml
env:
- name: HF_TOKEN
  valueFrom:
    secretKeyRef:
      name: hf-token
      key: HF_TOKEN
```

## Customization

### Increase Context Length

Edit `--max-model-len` in ServingRuntime args:

```yaml
args:
- --max-model-len=16384  # Increase context window (requires more GPU memory)
```

### Multi-GPU (Tensor Parallelism)

```yaml
args:
- --tensor-parallel-size=2  # Use 2 GPUs
```

## Troubleshooting

```bash
# Check pod logs
oc logs -n qwen-demo -l serving.kserve.io/inferenceservice=qwen25-7b -c kserve-container -f

# Check storage-initializer (model download) logs
oc logs -n qwen-demo -l serving.kserve.io/inferenceservice=qwen25-7b -c storage-initializer

# Check events
oc get events -n qwen-demo --sort-by='.lastTimestamp'

# Describe InferenceService
oc describe inferenceservice qwen25-7b -n qwen-demo
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `model type 'qwen3_5' not recognized` | Qwen3.5 uses new architecture not supported by Red Hat vLLM | Use Qwen2.5 instead, or wait for RHOAI update |
| `Insufficient nvidia.com/gpu` | No GPU resources available | Wait for GPU node autoscaling, or check MachineAutoscaler |
| `untolerated taint nvidia.com/gpu` | Pod missing GPU toleration | Ensure `tolerations` section is included |
| `OOMKilled` | Model too large for GPU memory | Use smaller model or increase `--max-model-len` |
| `Init:0/1` stuck | Model download in progress | Check storage-initializer logs, wait for download |

## Cleanup

```bash
# Delete the deployment
oc delete -f qwen25-7b-deployment.yaml

# (Optional) Immediately release GPU nodes to save costs
# Otherwise, MachineAutoscaler will scale down after ~10-15 min idle
oc scale machineset -n openshift-machine-api \
  $(oc get machineset -n openshift-machine-api -o name | grep g5) \
  --replicas=0
```
