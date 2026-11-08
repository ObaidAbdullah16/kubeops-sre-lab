{{- define "kubeops.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 10
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 3m
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - SkipDryRunOnMissingResource=true
{{- end -}}

{{- define "kubeops.helmApp" -}}
{{- $c := .chart -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  sources:
    - repoURL: {{ $c.repoURL }}
      chart: {{ $c.chart }}
      targetRevision: {{ $c.version | quote }}
      helm:
        releaseName: {{ .release }}
        valueFiles:
          - $values/gitops/platform/{{ .values }}
          {{- if ne .root.Values.profile "kind" }}
          - $values/gitops/platform/{{ .root.Values.profile }}/{{ .values }}
        ignoreMissingValueFiles: true
          {{- end }}
    - repoURL: {{ .root.Values.repoURL }}
      targetRevision: {{ .root.Values.targetRevision }}
      ref: values
  {{- include "kubeops.syncPolicy" . | nindent 2 }}
{{- end -}}

{{- define "kubeops.gitApp" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  source:
    repoURL: {{ .root.Values.repoURL }}
    targetRevision: {{ .root.Values.targetRevision }}
    path: {{ .path }}
  {{- include "kubeops.syncPolicy" . | nindent 2 }}
{{- end -}}
