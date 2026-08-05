# Helm charts

Helm charts for deploying applications and related Kubernetes workloads.

## Available charts

| Chart | Version | Description |
| --- | --- | --- |
| [laravel](charts/laravel/) | 0.7.4 | Deploys a Laravel application. |

## Requirements

- Helm 3
- A Kubernetes cluster configured in the current context
- A values file appropriate for the chart you are deploying
- A container image compatible with that chart's workloads

The charts do not build or provide application images. Images must be built separately and published to a registry accessible by the Kubernetes cluster.

## Generic usage

Replace <chart> and <release> with the chart and release you want to deploy:

~~~
helm upgrade --install <release> ./charts/<chart> \
  --namespace <namespace> \
  --create-namespace \
  --values values.yaml
~~~

For a chart published in a Helm repository, replace the local chart path with the configured repository reference.

Inspect available values before installing:

~~~
helm show values ./charts/<chart>
~~~

## Validation and rendering

Lint a chart:

~~~
helm lint ./charts/<chart> -f values.yaml
~~~

Render manifests without applying them:

~~~
helm template <release> ./charts/<chart> \
  --namespace <namespace> \
  --values values.yaml
~~~

Render manifests to a directory for inspection:

~~~
helm template <release> ./charts/<chart> \
  --namespace <namespace> \
  --values values.yaml \
  --output-dir ./rendered
~~~

Validate all charts with Chart Testing:

~~~
ct lint --config ct.yaml
~~~

## Inspecting a release

~~~
helm list --namespace <namespace>
helm get values <release> --namespace <namespace>
helm get manifest <release> --namespace <namespace>
kubectl get all --namespace <namespace>
~~~

Upgrade a release after changing its values:

~~~
helm upgrade <release> ./charts/<chart> \
  --namespace <namespace> \
  --values values.yaml
~~~

Remove a release:

~~~
helm uninstall <release> --namespace <namespace>
~~~

## Repository layout

~~~
charts/
└── <chart>/
    ├── Chart.yaml
    ├── README.md
    ├── values.yaml
    ├── values.schema.json
    └── templates/
~~~

When adding a chart, include its default values, schema, and chart-specific documentation in the chart directory.
