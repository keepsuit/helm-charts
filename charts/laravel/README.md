# Laravel Helm chart

A Helm chart for deploying Laravel applications and related workloads.

## Requirements

- Helm 3
- A Kubernetes cluster configured in the current context
- A Docker image compatible with the selected workload
- A values file containing global.image.repository and global.image.tag

The chart does not build or provide the application Docker image. The image must contain Laravel and its corresponding entrypoint.

## Installation

Create a values.yaml file:

~~~
global:
  image:
    repository: ghcr.io/example/my-laravel-app
    tag: "1.2.3"
    pullPolicy: IfNotPresent

app:
  port: 8080
  healthCheck:
    path: /up
    port: 8080
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi
~~~

Install the chart:

~~~
helm upgrade --install my-laravel ./charts/laravel \
  --namespace my-laravel \
  --create-namespace \
  --values values.yaml
~~~

For a chart published in a Helm repository, replace ./charts/laravel with the configured repository reference.

## Configuration

### Application

The app section configures the main Deployment, Service, and health checks:

~~~
app:
  enabled: true
  replicas: 2
  port: 8080
  service:
    enabled: true
    type: ClusterIP
    port: 80
  healthCheck:
    enabled: true
    path: /up
    port: 8080
    initialDelaySeconds: 30
    periodSeconds: 30
    timeoutSeconds: 5
    failureThreshold: 3
  autoscaling:
    enabled: false
    minReplicas: 1
    maxReplicas: 10
    targetCPUUtilizationPercentage: 60
~~~

The chart uses the same HTTP health check for the application's readiness and liveness probes. The endpoint should therefore be lightweight and reliable.

### Environment variables and Secrets

Environment variables can be defined globally or for an individual workload:

~~~
global:
  env:
    - name: APP_ENV
      value: production
  envFrom:
    - secretRef:
        name: my-laravel-secrets

app:
  env:
    - name: LOG_CHANNEL
      value: stderr
~~~

Global environment variables are applied to the chart workloads. Chart-owned variables such as APP_VERSION and CONTAINER_ROLE cannot be overridden.

To mount files from a Secret:

~~~
global:
  secretVolumes:
    - name: my-secret
      mountPath: /var/www/html/storage
      items:
        - key: credentials.json
          path: credentials.json
~~~

### Workers

Workers are defined in the workers array. Supported types are queue, horizon, scheduler, and combined:

~~~
global:
  workerCommand:
    useWrapper: true
    binary: docker-laravel-worker

workers:
  - name: default
    type: queue
    enabled: true
    replicas: 2
    queue: default
    queueOptions:
      sleep: 3
      tries: 3
      timeout: 90
      maxTime: 3600
    # omit to inherit workerResources.queue (see values.yaml)
    resources:
      requests:
        cpu: 25m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 768Mi

  - name: horizon
    type: horizon
    enabled: true
    replicas: 1
~~~

The combined type requires global.workerCommand.useWrapper: true. Commands are passed as arguments to the image entrypoint.

### FrankenPHP and Octane

To use Laravel Octane:

~~~
app:
  octane:
    enabled: true
    workers: auto
    logLevel: info
~~~

Always configure resources and health checks according to the number of threads/workers and the container memory limit.

### Reverb

Enable Reverb with a dedicated Deployment and Service:

~~~
reverb:
  enabled: true
  replicas: 1
  port: 8080
  service:
    enabled: true
    type: ClusterIP
    port: 8080
~~~

### Ingress

Ingress routes are configured through routing.ingress.routes:

~~~
routing:
  ingress:
    enabled: true
    className: nginx
    annotations:
      nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
    routes:
      - service: app
        host: example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - example.com
~~~

Routes can target the app or reverb Service.

### Post-deploy hooks

To run commands after deployment:

~~~
hooks:
  postDeploy:
    enabled: true
    commands:
      - php artisan migrate --force -n
      - php artisan db:seed --force -n
~~~

## Validation and rendering

Lint the chart:

~~~
helm lint ./charts/laravel -f values.yaml
~~~

Render manifests without applying them:

~~~
helm template my-laravel ./charts/laravel \
  --namespace my-laravel \
  --values values.yaml
~~~

Render manifests to a directory for inspection:

~~~
helm template my-laravel ./charts/laravel \
  --namespace my-laravel \
  --values values.yaml \
  --output-dir ./rendered
~~~

## Release management

~~~
helm list --namespace my-laravel
helm get values my-laravel --namespace my-laravel
helm get manifest my-laravel --namespace my-laravel
kubectl get deploy,svc,ingress --namespace my-laravel
~~~

Upgrade the release after changing the values:

~~~
helm upgrade my-laravel ./charts/laravel \
  --namespace my-laravel \
  --values values.yaml
~~~

Remove the release:

~~~
helm uninstall my-laravel --namespace my-laravel
~~~

## References

- [Default values](values.yaml)
- [Values schema](values.schema.json)
- [Changelog and version 0.7 migration guide](CHANGELOG.md)
- [Debug configuration](debug_values.yaml)
