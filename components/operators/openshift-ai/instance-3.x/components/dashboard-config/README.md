# dashboard-config

## Purpose

This component configures the OpenShift AI Dashboard settings via OdhDashboardConfig.

## Configuration

Enables the following dashboard features:
- Model Registry
- Model Catalog
- KServe Metrics
- GenAI Studio
- Model as Service
- LM Eval

## Usage

Add this component to your overlay's `kustomization.yaml`:

```yaml
components:
  - ../../components/dashboard-config
```
