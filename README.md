# Helm charts

Helm charts for deploying applications and related Kubernetes workloads.

## Available charts

| Chart | Version | Description |
| --- | --- | --- |
| [laravel](charts/laravel/) | 0.7 | Deploys a Laravel application. |
| [web](charts/web/) | 0.1 | Deploys a stateless HTTP application. |

## Requirements

- Helm 4
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

Run the charts' YAML manifest regression checks with Helm 4 and
[helm-unittest](https://github.com/helm-unittest/helm-unittest):

~~~sh
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.2.1 --verify=false
helm unittest --strict ./charts/laravel
helm unittest --strict ./charts/web
~~~

Helm 4 requires `--verify=false` for the Git-based plugin installation, as documented by
helm-unittest. The suites under `charts/<chart>/tests/` run locally without a cluster and
are excluded from chart packages. The Laravel suites cover probes, Octane, workers, HPA/KEDA, Reverb,
services, disruption budgets, ingress/TLS, deployment hooks, shared pod settings, and
invalid configuration.

Example values for real deployments live in `examples/`.

The `Chart CI` GitHub Actions workflow runs strict Helm lint and these suites on pull
requests and pushes to `main`, and can also be started manually. CI uses Helm 4.3.0 and
helm-unittest 1.2.1; it does not install a release or access a Kubernetes cluster.

Helm's built-in `helm test <release>` instead runs test workloads against an installed
release; it is intended for deployment smoke checks rather than these rendering checks.

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
