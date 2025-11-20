Grafana dashboard and monitoring notes for the `cilium-demo` nginx service

This folder contains a Grafana dashboard JSON and guidance to observe the `nginx-demo` deployment you created for learning Cilium.

Files
- `nginx-cilium-dashboard.json` - Grafana dashboard you can import into Grafana.

What the dashboard shows
- Ready Pod Count (from kube-state-metrics)
- Pod restarts (from kube-state-metrics)
- CPU usage (from cAdvisor metrics / container_cpu_usage_seconds_total)
- Memory usage (from cAdvisor metrics / container_memory_usage_bytes)
- HTTP probe success (optional, requires a Blackbox exporter + Prometheus probe job)

Quick setup (assumes you have a running Kubernetes cluster and `kubectl` configured)

1) Install Prometheus + Grafana (kube-prometheus-stack via Helm)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

This installs Prometheus, Alertmanager and Grafana with a default configuration. The chart provides CRDs for `ServiceMonitor` and a Grafana dashboard sidecar if you want to mount dashboards via ConfigMaps.

2) Ensure metrics are available
- `kube-state-metrics` and `kubelet / cAdvisor` metrics are provided by the `kube-prometheus-stack` chart by default.
- The dashboard uses metrics with labels like `namespace="cilium-demo"` and `pod=~"nginx-demo.*"`.

3) Optional: deploy Blackbox exporter to probe HTTP from Prometheus

If you want the HTTP probe panel to work, deploy the Blackbox exporter and configure Prometheus to probe your service. Example manifest is in `../monitoring/blackbox-deployment.yaml` (apply it into a `monitoring` namespace). You'll also need to add a `ServiceMonitor` or `additionalScrapeConfigs` for Prometheus that instructs it to call the blackbox exporter with the target URL `http://nginx-demo.cilium-demo.svc.cluster.local` and label the resulting metrics with `job=blackbox-probe-nginx-cilium-demo`.

4) Import the dashboard
- Open Grafana (the Helm chart exposes a `Grafana` service in the `monitoring` namespace. You can port-forward:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# then open http://localhost:3000
```

- Login using the chart's default credentials (see helm chart notes; often `admin` and a password stored in a secret `monitoring-grafana`)
- In Grafana, go to Dashboards > Import, paste the JSON from `nginx-cilium-dashboard.json` or upload the file.

5) Adjust the dashboard's datasource
- If Grafana's Prometheus datasource is named something other than `Prometheus`, select it when importing the dashboard.

Example Prometheus probe config (manual step)
- The Blackbox exporter is usually probed by Prometheus using an HTTP `probe` module. A `ServiceMonitor` alone won't trigger a probe to an external target; you need to configure Prometheus `additionalScrapeConfigs` or use the `blackbox_exporter` as a target with `params` telling it which URL to probe.

Resources
- kube-prometheus-stack chart: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Blackbox exporter: https://github.com/prometheus/blackbox_exporter
- Grafana provisioning sidecar (for automatically loading dashboards via ConfigMaps) is supported by the kube-prometheus-stack chart.

If you'd like, I can:
- Add a `ConfigMap` + labels so the dashboard is auto-imported by the Grafana sidecar deployed with the Helm chart.
- Provide a complete `ServiceMonitor`/`PodMonitor` + `additionalScrapeConfigs` example to get the blackbox probe working end-to-end.
- Create a Helm values snippet to enable the dashboard automatically when installing the chart.
