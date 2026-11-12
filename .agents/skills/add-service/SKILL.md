---
name: add-service
description: >-
  Registers a new OpenID Connect (OIDC) client in home-lab/authelia across clients.yaml,
  tracked secret placeholders, docker-compose.yml, .gitlab-ci.yml, and shared GitLab CI/CD
  variables. Use when onboarding an OIDC-enabled homelab service to Authelia SSO.
---

# Onboard OIDC Client (`home-lab/authelia`)

Use this skill when registering or updating an OpenID Connect (OIDC) relying party in `home-lab/authelia` (`https://auth.xbhl.online`). Operate strictly via stateless `git -C "<authelia_dir>"` and `glab` CLI—never SSH to hosts, probe `:2375`, print secrets, or invoke `python3`/`ruby`/`node` one-liners.

## 1. Branching & Merge Order
1. Fetch latest `main` and create branch `feat/<service>-oidc` off `origin/main` (use `chore/<service>-oidc` when updating an existing client):
   ```bash
   git -C "<authelia_dir>" fetch --prune origin
   git -C "<authelia_dir>" checkout -B "feat/<service>-oidc" origin/main
   ```
2. **Deployment Prerequisite**: `feat/<service>-oidc` MUST be merged and deployed to `home-lab/authelia` **BEFORE** the consuming service deploys so OIDC discovery and client authentication succeed on initial startup.

## 2. Register Client in `src/authelia-config/clients.yaml`
1. Append the client under `identity_providers.oidc.clients` (`<service>` lowercase slug, `<SERVICE>` uppercase snake_case; map admin group `Domain Power Users` in the consuming app):
   ```yaml
         - client_id: "<service>"
           client_name: "<Display Name>"
           client_secret: '{{ secret "/run/secrets/<SERVICE>_OAUTH_CLIENT_SECRET" }}'
           consent_mode: "implicit"
           public: false
           authorization_policy: "two_factor"
           require_pkce: true
           pkce_challenge_method: "S256"
           redirect_uris:
             - "https://<service_domain><callback_path>"
           scopes: ["openid", "profile", "email", "groups"]
           response_types: ["code"]
           grant_types: ["authorization_code"]
           access_token_signed_response_alg: "none"
           userinfo_signed_response_alg: "none"
           token_endpoint_auth_method: "client_secret_basic" # or "client_secret_post" per upstream app
   ```
   *(Omit `require_pkce` / `pkce_challenge_method` if the upstream relying party does not support PKCE.)*
2. **Authelia 4.39+ ID Token Claims (`claims_policies`)**: Authelia 4.39+ omits `email`, `name`, `groups`, and `preferred_username` from `id_token` by default (returning them only via `/api/oidc/userinfo`). Whenever an app reads user profile/group claims or custom user attributes directly from `id_token` (e.g., Grafana `role_attribute_path`), define `identity_providers.oidc.claims_policies.<service>` (`id_token: ['email', 'name', 'groups', 'preferred_username']`) and set `claims_policy: "<service>"` on the client entry.
3. **CORS Origins (`src/authelia-config/identity_providers.yaml`)**: `cors.allowed_origins_from_client_redirect_uris: true` authorizes redirect URI origins automatically; add to `cors.allowed_origins` only if a browser SPA calls OIDC endpoints from a separate origin.

## 3. Wire Secret Placeholder, Compose & CI Artifact Generation
1. **Tracked Placeholder**: Create `src/secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET` containing `PLACEHOLDER` so local Compose validation resolves the file path.
2. **`src/docker-compose.yml`**:
   - Append `"<SERVICE>_OAUTH_CLIENT_SECRET"` to `services.authelia.secrets`.
   - Register the file secret under top-level `secrets:`:
     ```yaml
     <SERVICE>_OAUTH_CLIENT_SECRET:
       file: ./secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET
     ```
3. **`.gitlab-ci.yml`**: Under `setup:generate-build-artifacts` (`# services`), append a single-quoted list item:
   ```yaml
   - 'printf "%s\n" "${<SERVICE>_OAUTH_CLIENT_SECRET:?<SERVICE>_OAUTH_CLIENT_SECRET is not set}" > $BUILD_ARTIFACTS_DIR/secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET'
   ```

## 4. Shared Secret Provisioning, Validation & Merge Request
1. **Provision Shared Secret**: Idempotently generate and store `<SERVICE>_OAUTH_CLIENT_SECRET` (`masked: true`, `raw: true`, `protected: false`, zero plaintext output) in both GitLab projects using the `home-lab/automations` helper:
   ```bash
   "<automations_skills_root>/implement-issue/scripts/provision-gitlab-secret.sh" base64 32 \
     "home-lab/authelia:<SERVICE>_OAUTH_CLIENT_SECRET" \
     "<project_path>:<SERVICE>_OAUTH_CLIENT_SECRET"
   ```
2. **Validate YAML & Config**: Validate `src/authelia-config/clients.yaml`, `src/docker-compose.yml`, and `.gitlab-ci.yml` with `yq` or `yamllint` (never `python3`/`ruby`/`node`). Pushing triggers CI job `test:authelia:validate-config`, which renders `{{ secret ... }}` and `{{ env ... }}` (`X_AUTHELIA_CONFIG_FILTERS=template`) and runs `authelia config validate --config src/authelia-config/`.
3. **Commit, Push & Open MR**:
   ```bash
   git -C "<authelia_dir>" add src/authelia-config/ src/secrets/services/ src/docker-compose.yml .gitlab-ci.yml
   git -C "<authelia_dir>" commit -m "feat(oidc): register <service> oidc client"
   git -C "<authelia_dir>" push -u origin "feat/<service>-oidc"
   glab mr create --source-branch "feat/<service>-oidc" --target-branch "main" \
     --title "feat(oidc): register <service> oidc client" \
     --description-file "/tmp/homelab-work/mr-desc-authelia-<service>-oidc.md" \
     --label "type::feature" --remove-source-branch --yes \
     -H "https://gitlab.intranet.xbhl.online/home-lab/authelia" \
     -R "https://gitlab.intranet.xbhl.online/home-lab/authelia"
   git -C "<authelia_dir>" checkout -f origin/main
   ```
