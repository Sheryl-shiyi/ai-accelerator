# Custom Model Catalog

This component configures a custom model catalog for OpenShift AI, implementing **model whitelisting** by defining only approved models that users can discover and deploy.

## Purpose

- **Model Governance**: Only pre-approved models appear in the AI Hub Catalog
- **Compliance**: Ensure only validated, licensed models are available
- **Simplification**: Users see a curated list instead of thousands of models

## Why Use `resources` Instead of `patches`?

The `model-catalog-sources` ConfigMap is:
- Created and managed by `model-registry-operator`
- Located in `rhoai-model-registries` namespace (not in our kustomize base)
- Requires complete replacement of `data.sources.yaml`

Since we're replacing the entire data content (not just modifying a field), using `resources` is cleaner. The full labels are preserved to maintain operator compatibility.

## Included Models

| Model | Provider | License | Notes |
|-------|----------|---------|-------|
| Qwen/Qwen2.5-7B-Instruct | Alibaba Cloud | Apache-2.0 | ✅ Verified |
| Qwen/Qwen2.5-14B-Instruct | Alibaba Cloud | Apache-2.0 | |
| Qwen/Qwen3.5-4B | Alibaba Cloud | Apache-2.0 | ⚠️ Requires newer vLLM |
| Qwen/Qwen3.6-35B-A3B | Alibaba Cloud | Apache-2.0 | MoE model |
| mistralai/Mistral-7B-Instruct-v0.3 | Mistral AI | Apache-2.0 | |
| RedHatAI/Llama-3.1-8B-Instruct | Red Hat / Meta | Llama 3.1 | OCI format |
| google/gemma-4-31B | Google | Gemma ToU | |

## Usage

### Via GitOps (Recommended)

Add this component to your overlay's `kustomization.yaml`:

```yaml
components:
  - ../../components/custom-model-catalog
```

### Manual Apply

```bash
oc apply -f model-catalog-configmap.yaml

# Force reload of model-catalog pods
oc delete pod -l component=model-catalog -n rhoai-model-registries
```

## Adding New Models

Edit `model-catalog-configmap.yaml` and add entries to the `approved-models.yaml` section:

```yaml
- name: org/model-name
  description: |
    Model description here
  readme: |
    # Model Name
    Detailed documentation...
  provider: Provider Name
  logo: ""
  license: apache-2.0
  licenseLink: https://license-url
  libraryName: transformers
  artifacts:
    - uri: hf://org/model-name
```

## Verification

After applying, check the OpenShift AI Dashboard:

1. Go to **AI Hub → Catalog**
2. Click **Sheryl Selected models** filter
3. Only whitelisted models should appear

## References

- [Configuring model catalog sources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/configuring-model-catalog-sources-in-openshift_working-model-catalog)
- [Sample catalog format](https://github.com/opendatahub-io/model-registry/blob/main/manifests/kustomize/options/catalog/base/sample-catalog.yaml)
