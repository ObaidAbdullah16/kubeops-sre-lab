# GD-04 - Guardrails stop a bad deploy

**Story:** under time pressure someone tries to deploy an insecure container, and
later an image that did not come from CI.

```bash
bash chaos/bad-deploy.sh
```

| Attempt | Expected result | Policy |
|---|---|---|
| `nginx:latest`, privileged, no probes/limits | REJECTED with 5 reasons | `restrict-registries`, `disallow-latest-tag`, `restricted-security-context`, `require-probes`, `require-requests-limits` + Pod Security Admission |
| our image by tag | REJECTED: must use a digest | `verify-demo-image-signature` (`verifyDigest`) |
| our image by an unsigned digest | REJECTED: no valid Sigstore signature from `image.yml@main` | `verify-demo-image-signature` |

Then show the positive path: the real Deployment in `gitops/apps/demo` is accepted
because the Image workflow signed it with keyless cosign (GitHub OIDC identity,
recorded in the public Rekor transparency log):

```bash
cosign verify ghcr.io/obaidabdullah16/kubeops-demo-app@sha256:<digest> \
  --certificate-identity https://github.com/ObaidAbdullah16/kubeops-sre-lab/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Discussion: admission control vs CI checks (defence in depth), why digests, what
an exception process (`PolicyException`) would look like.
