# Sending alerts somewhere

Out of the box Alertmanager routes everything to a `null` receiver, so alerts are
visible at http://localhost:9093 and in Grafana but nobody is paged. To page:

## Slack

1. Create a Slack incoming webhook (Slack → Apps → Incoming Webhooks).
2. Store it in the cluster (never in Git):

   ```bash
   kubectl -n monitoring create secret generic alertmanager-slack \
     --from-literal=url='https://hooks.slack.com/services/...'
   ```

3. In `gitops/platform/kube-prometheus-stack.yaml` mount the secret and add a receiver:

   ```yaml
   alertmanager:
     alertmanagerSpec:
       secrets: [alertmanager-slack]   # mounted at /etc/alertmanager/secrets/alertmanager-slack/
     config:
       route:
         routes:
           - receiver: slack
             matchers: ['severity = "critical"']
       receivers:
         - name: "null"
         - name: slack
           slack_configs:
             - api_url_file: /etc/alertmanager/secrets/alertmanager-slack/url
               channel: "#alerts"
               send_resolved: true
               title: '{{ .CommonLabels.alertname }} ({{ .Status }})'
               text: '{{ range .Alerts }}{{ .Annotations.summary }} - {{ .Annotations.runbook_url }}{{ "\n" }}{{ end }}'
   ```

4. Commit and push: Argo CD applies it within a minute.

## IncidentScribe AI (companion project)

`incidentscribe-ai` accepts Alertmanager webhooks on `POST /incidents` and returns
an AI-written incident summary with matching runbook links. Add a receiver:

```yaml
receivers:
  - name: incidentscribe
    webhook_configs:
      - url: https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/incidents
        send_resolved: false
```

The kind cluster can reach the public API Gateway URL directly.

Note: `POST /incidents` is IncidentScribe's **public demo** route. It summarises and stores the
alert (with a `WEB-` ID) but, by design, never posts to Slack, because anyone on the internet can
call it. The summaries of your lab alerts are kept for 30 days in IncidentScribe's
`incidentscribe-incidents` DynamoDB table (console → DynamoDB → Explore items). For Slack messages from Alertmanager,
route critical alerts to Slack directly (above), or add an authenticated route to IncidentScribe
(see its documentation, exercise 8).
