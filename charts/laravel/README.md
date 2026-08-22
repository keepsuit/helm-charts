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

### Queue autoscaling with KEDA

Workers of type queue and horizon can scale on queue depth instead of CPU, down to zero
replicas. This needs [KEDA](https://keda.sh) installed in the cluster and an image that
serves `GET /_metrics/queue-size` on port 8081.

Enable the endpoint, then switch the worker to the keda mode:

~~~
global:
  metrics:
    enabled: true

workers:
  - name: default
    type: queue
    queue: default
    autoscaling:
      enabled: true
      mode: keda
      minReplicas: 0     # default for mode keda
      maxReplicas: 5
      targetValue: 10    # queue depth per replica
      cooldownPeriod:    # seconds idle before scaling to zero, KEDA default is 300
~~~

global.metrics.enabled adds container port 8081 to the app pods, labels them
laravel.keepcloud.io/metrics: "true", and renders a dedicated <release>-metrics Service.
The ScaledObject polls that Service. For queue workers the worker queue is passed through
as ?queues=..., so the scaler counts exactly the queues the worker consumes; horizon workers
send no parameter and the endpoint discovers the queues from the horizon config.

Constraints, all enforced at render time:

- mode: keda requires global.metrics.enabled and app.enabled. The endpoint is served by the
  app pods, so a release without a web tier has nothing to poll.
- Only queue and horizon workers. Scheduler and combined workers cannot autoscale at all.
- mode: keda replaces the HorizontalPodAutoscaler, it is never rendered alongside one.

If the metrics endpoint fails, the ScaledObject falls back to 1 replica after 3 consecutive
failures, so a broken metric leaves a worker running rather than a queue unattended.

KEDA does not document whether this fallback also applies while a worker sits at zero
replicas. Verify it on the first app you roll this out to: with the worker scaled to zero and
a job queued, delete the app pods and confirm a worker still starts. If it does not, keep
minReplicas: 1 on any queue where a stall is not acceptable, queue-depth scaling is still a
better signal than CPU.

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
