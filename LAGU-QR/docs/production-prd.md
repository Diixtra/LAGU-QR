# PRD: LAGU-QR Production SaaS

## 1. Overview

LAGU-QR is currently a single-purpose infrastructure claim for hosting a wedding programme image behind a QR code. The current repo contains:

- `claim.yaml`: a Crossplane `XImageHosting` claim for one S3-hosted programme image.
- `kustomization.yaml`: Flux/Kustomize wiring for that claim.
- `scripts/generate-qr.py`: a local QR image generator.
- `docs/superpowers/*`: original implementation/design notes.

The production product, QRBuddy, should become a self-service SaaS that lets customers create QR-linked hosted assets for general use cases including weddings, events, business menus, programmes, flyers, and other frequently updated documents/images. The product should actively inspire customers with use-case examples during marketing, onboarding, and project creation. Infrastructure can continue to be provisioned through Crossplane XRDs, but the user-facing experience needs authentication, billing, account/workspace management, usage limits, custom domains, and operational controls.

## 2. Product Objectives

| Objective | Description | Priority |
|---|---|---|
| Self-service onboarding | Customers can sign up, create a project, upload content, and generate a QR code without manual Git/Crossplane work. | MVP |
| Secure customer accounts | Use Better Auth for user accounts, sessions, organizations/workspaces, and admin access. | MVP |
| Paid plans | Support subscription tiers with usage limits and upgrade paths. | MVP |
| Reliable asset hosting | Serve QR targets from stable URLs with high availability and low latency. | MVP |
| Safe upload/update flow | Authenticated customers can replace assets without exposing public upload endpoints. | MVP |
| Custom branding/domains | Higher-tier customers can use branded pages and custom domains. | Post-MVP / Pro |
| Scalable tenant isolation | Provide sane default tenant isolation now, with optional AWS account-per-customer for larger customers if feasible. | Post-MVP / Enterprise |

## 3. Target Audience

### Primary Users

- Couples and event organizers who need a QR code that always points to the latest programme, menu, itinerary, or information sheet.
- Small businesses needing editable QR-linked flyers, menus, service documents, or posters.
- Agencies or planners managing QR assets for multiple clients/events.

### Internal Users

- Platform admin/operator managing tenants, plans, abuse, infrastructure health, and support.

## 4. Current State Analysis

### Existing Capabilities

- Crossplane-backed infrastructure provisioning via `platform.diixtra.com/v1alpha1` `XImageHosting`.
- Public S3 object read URL used as QR target.
- Lambda/API Gateway upload flow in forge-side composition.
- Password-protected upload support appears in the current XRD/claim via `spec.uploadPassword`.
- QR generation is local and manual through `scripts/generate-qr.py`.

### Current Gaps for Production

- No web app or customer dashboard in this repo.
- No persistent product database for users, projects, assets, subscriptions, domains, or audit logs.
- No customer auth, account recovery, roles, or team access.
- No billing/subscription enforcement.
- No automated QR generation in the product UI.
- No multi-tenant lifecycle management from app state to Crossplane claim creation.
- No public landing/pricing pages.
- No analytics for QR scans, asset views, usage, or conversions.
- No production-grade domain, CDN, cache invalidation, malware/file validation, abuse controls, or support flows.

## 5. Proposed Product Scope

### MVP

The MVP should support one authenticated customer creating one or more QR projects, uploading an image/PDF, and downloading a QR code for a stable public URL under a product-controlled domain. The initial hosted URL can use `qr.diixtra.com`, with the domain stored as an environment/config variable so it can be changed to `qrbuddy.app` when ready.

MVP features:

- Better Auth email/password login.
- Customer workspace/account model.
- Project creation: name, slug, event type, region, default asset key.
- Authenticated upload and replacement of a hosted asset.
- Public QR URL under a configurable product domain/subdomain, initially a subdomain of `diixtra.com`.
- QR code generation and download as PNG/SVG.
- Stripe subscription checkout and webhook handling.
- Basic tier enforcement: project count, storage, monthly scans/views, file size.
- Crossplane claim creation/update per project.
- Admin view for projects, claims, customers, and provisioning status.

### Post-MVP

- Branded landing pages and templates.
- Scan analytics dashboard.
- Multi-file event pages.
- Agency/client workspace model.
- Enterprise isolation using dedicated AWS accounts where justified.

### Use-case Inspiration

The product should not present itself as abstract file hosting only. Marketing pages, onboarding, and project creation should suggest concrete use cases such as:

- Wedding programmes and order-of-day sheets.
- Restaurant/bar menus and seasonal price lists.
- Event schedules, maps, speaker agendas, and conference handouts.
- Funeral/order-of-service documents.
- Property brochures and sales sheets.
- Posters/flyers where printed QR codes need editable content.
- Manuals, setup instructions, safety sheets, and customer-facing PDFs.
- Portfolio/CV/profile documents.

Use-case copy and visual assets should be maintained in the `design-platform` repo, with exported brand/design assets consumed by the application code.

## 6. User Stories

### Customer Onboarding

- As a visitor, I can view pricing and start a free/paid trial.
- As a customer, I can create an account using email/password.
- As a customer, I can recover my password and verify my email.
- As a customer, I can create a workspace for my event/business.

### QR Project Management

- As a customer, I can create a QR project with a human-readable name and slug.
- As a customer, I can upload an image or PDF to use as the QR destination.
- As a customer, I can replace the hosted file without changing the QR code.
- As a customer, I can download the QR code in PNG and SVG formats.
- As a customer, I can see whether the QR destination is live.

### Billing

- As a customer, I can choose a plan during onboarding.
- As a customer, I can upgrade when I hit usage limits.
- As an admin, I can see subscription status and usage by account.

### Pro / Enterprise

- As a Pro customer, I can connect a custom domain.
- As an agency, I can manage multiple client projects under one account. This is not required for MVP, but should remain in the backlog.
- As an enterprise customer, I can request stronger infrastructure isolation.

## 7. Functional Requirements

### 7.1 Authentication and Account Management

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| AUTH-001 | Implement Better Auth server configuration. | MVP | App exposes auth routes, sessions, sign-up, sign-in, sign-out. |
| AUTH-002 | Enable email/password auth. | MVP | User can register with email, password, and name. |
| AUTH-003 | Store users, sessions, accounts, and verification records in production DB. | MVP | Better Auth migration/schema exists and runs in deployment. |
| AUTH-004 | Add email verification and password reset. | MVP | Verification/reset emails are sent through configured email provider. |
| AUTH-005 | Support workspace/organization membership. | MVP | A user belongs to at least one workspace; projects are workspace-scoped. |
| AUTH-006 | Add admin role or admin plugin equivalent. | MVP | Admin users can view/manage all tenants. |
| AUTH-007 | Add OAuth sign-in. | Later | Google sign-in works and links accounts safely. |

Implementation note: use Better Auth with a durable SQL database, environment variables `BETTER_AUTH_SECRET` and `BETTER_AUTH_URL`, secure cookies in production, and the Better Auth organization plugin for app-level teams/workspaces. Team/shared asset access should be supported, but every team member must have a paid account or be covered by a paid seat entitlement.

### 7.2 Billing and Plans

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| BILL-001 | Integrate Stripe Checkout for subscriptions. | MVP | User can subscribe to a selected plan. |
| BILL-002 | Handle Stripe webhooks. | MVP | Subscription created/updated/cancelled events update local account entitlement state. |
| BILL-003 | Enforce plan limits before project creation/upload. | MVP | Users receive a clear error when they have too many files/projects or the file is too large, with an upgrade prompt where appropriate. |
| BILL-004 | Expose customer billing portal. | MVP | User can manage payment method/cancel plan. |

Suggested initial tiers:

| Tier | Target | Limits | Features |
|---|---|---|---|
| Starter | One-off personal events and lightweight business use | £1.99/month; `STARTER_QR_PROJECT_LIMIT=10`; `STARTER_MAX_FILE_SIZE_MB=TBD`; `STARTER_TOTAL_STORAGE_MB=TBD`; all limits configurable | Stable QR URL, image/PDF upload, QR download, last 2 versions retained for 30 days |
| Pro | Businesses/planners | £5.99/month; `PRO_QR_PROJECT_LIMIT=50`; `PRO_MAX_FILE_SIZE_MB=TBD`; `PRO_TOTAL_STORAGE_MB=TBD`; all limits configurable | Custom domains, higher limits, analytics, last 2 versions retained for 30 days |
| Scale | Heavier business/high usage | £9.99/month; `SCALE_QR_PROJECT_LIMIT=100`; `SCALE_MAX_FILE_SIZE_MB=TBD`; `SCALE_TOTAL_STORAGE_MB=TBD`; all limits configurable | Highest self-serve limits, custom domains, team sharing, advanced analytics |
| Enterprise | Regulated/high isolation | Custom | Dedicated AWS account option, SLA, SSO, custom contracts |

### 7.3 QR Project Lifecycle

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| PROJ-001 | Create project from dashboard. | MVP | Project row is persisted and linked to workspace. |
| PROJ-002 | Provision hosting infrastructure via Crossplane claim. | MVP | App creates/updates claim or calls an internal provisioning service; claim status syncs back. |
| PROJ-003 | Generate stable public URL. | MVP | URL does not change when file is replaced. |
| PROJ-004 | Generate QR codes. | MVP | User can download PNG and SVG QR assets. |
| PROJ-005 | Replace uploaded asset. | MVP | Latest upload is served at existing QR URL. |
| PROJ-006 | Delete/inactivate project. | MVP | Inactive projects destroy public resources and move the XRD/claim record into an archived or deactivated state for audit/support reference. |

### 7.4 Upload and Asset Management

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| ASSET-001 | Authenticated upload flow. | MVP | Only authenticated project members can upload/replace assets. |
| ASSET-002 | File validation. | MVP | Images and PDFs are accepted; unsupported MIME types and files over plan limits are rejected. |
| ASSET-003 | Malware/abuse scanning. | MVP | Uploaded files are scanned before becoming public, especially PDFs and externally supplied images. |
| ASSET-004 | Version history. | MVP | Keep the last 2 versions for 30 days to support accidental replacement recovery. |
| ASSET-005 | Public delivery with private origin. | MVP | QR target can be accessed without login, but object storage buckets remain private and are only reachable through the approved CDN/proxy layer. |

### 7.5 Domains and Delivery

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| DOM-001 | Default hosted URLs. | MVP | Projects get a URL under configurable `PUBLIC_QR_BASE_DOMAIN`; initial value is `qr.diixtra.com`, target product domain is `qrbuddy.app`. |
| DOM-002 | CDN delivery. | MVP | Public assets are served through CloudFront or an equivalent CDN/object-delivery layer instead of raw S3. S3 buckets must be private and accessed via Origin Access Control/Origin Access Identity or equivalent private-origin controls. |
| DOM-003 | Cost-optimized caching. | MVP | Static assets use cache-control headers, compression where applicable, and long-lived CDN caching to reduce object storage request/egress costs. Cache policy is configurable per asset/project type. |
| DOM-004 | Custom domain setup. | Pro/Scale | Higher-tier users can add a custom domain, verify DNS, and get HTTPS certificate. |
| DOM-005 | Cache invalidation on replacement. | MVP | New uploads appear promptly after replacement using versioned object keys/manifests where possible; paid CDN invalidations are avoided unless necessary. |

### 7.6 Analytics

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| AN-001 | Track project views/scans. | MVP | Dashboard shows basic view count by project. |
| AN-002 | Show time-series analytics. | Pro | User can view scans by day/device/referrer/country where legally/technically available. |
| AN-003 | Export analytics. | Scale | CSV export available. |

### 7.7 Admin and Operations

| ID | Requirement | Priority | Acceptance Criteria |
|---|---|---|---|
| OPS-001 | Admin tenant list. | MVP | Admin can search users/workspaces/projects. |
| OPS-002 | Provisioning status sync. | MVP | App shows claim/resource status and errors. |
| OPS-003 | Manual suspend/delete. | MVP | Admin can suspend abusive or unpaid projects. |
| OPS-004 | Audit logs. | Later | Project uploads, billing changes, domain changes, and admin actions are recorded. |

## 8. Technical Architecture

### Recommended Components

- Web app: Next.js or similar TypeScript full-stack framework.
- Auth: Better Auth.
- Database: Postgres for users, workspaces, projects, entitlements, usage, audit logs.
- Billing: Stripe.
- Provisioning: Crossplane XRD claims remain the source for AWS resource creation.
- Platform infrastructure: `diixtra-forge` must manage shared QRBuddy platform infrastructure, including Cloudflare DNS records, deployment resources, secrets, and any Crossplane/Flux resources required by the app.
- Object hosting: private S3 buckets or equivalent private object storage, fronted by CloudFront or another CDN/proxy layer for production. Raw public S3 bucket/object access should not be used.
- File scanning: malware scanning pipeline for images and PDFs before publishing assets. Initial preferred option is ClamAV, likely via an async worker or S3-triggered scanner; remain open to managed/third-party scanning if ClamAV operation becomes burdensome.
- DNS/custom domains: Cloudflare-managed DNS for `qr.diixtra.com` and `qrbuddy.app`; Route53/Cloudflare integration plus ACM certificates for higher-tier custom domains.
- Async jobs: queue/worker for provisioning status sync, webhooks, usage aggregation, domain checks.

### Cost-Optimized Asset Delivery

The current single public S3 bucket pattern is too expensive/risky for production because every public object read can hit the bucket directly and there is limited control over caching, abuse, and egress. Production delivery should use private origins and a cache-first public edge.

Requirements:

- Buckets/origins must be private by default. Disable S3 public access and expose assets only through CloudFront, Cloudflare, Bunny CDN, Fastly, or an equivalent delivery layer.
- Preferred AWS-native option: CloudFront in front of S3 using Origin Access Control (OAC), HTTPS-only viewer policy, managed or custom cache policies, and per-project path routing.
- Use stable public QR URLs that resolve to a lightweight redirect/manifest or current asset pointer, while storing uploaded files under immutable versioned object keys. This keeps printed QR codes stable while allowing cache-friendly asset URLs.
- Prefer versioned object keys over frequent CDN invalidations. On replacement, update the project pointer/manifest and serve the new immutable asset URL. Use explicit invalidation only for urgent corrections or when pointer TTLs require it.
- Set conservative default cache headers: long TTL for immutable asset versions, short TTL for the stable pointer/manifest route, and `stale-while-revalidate`/`stale-if-error` where supported.
- Track CDN cache-hit ratio, origin request count, origin egress, invalidation count/cost, and per-project bandwidth so pricing and abuse controls can be adjusted.
- Add rate limits, bot/abuse protection, and hotlink controls where supported to prevent one QR project from driving runaway costs.
- Evaluate non-AWS/hyperscaler alternatives if they materially reduce cost or operational load, including Cloudflare CDN/R2, Bunny Storage/CDN, Backblaze B2 + CDN, or managed object delivery providers. The architecture should keep the storage/CDN provider behind an abstraction so the product is not locked into public S3 URLs.

Initial recommendation for MVP: private S3 + CloudFront OAC for fastest integration with existing Crossplane/AWS work, with Cloudflare DNS in front as needed. Revisit Cloudflare R2 or Bunny CDN once real traffic/cost data exists.

### App Data Model Draft

| Entity | Purpose |
|---|---|
| User | Better Auth user identity. |
| Workspace | Customer account/team; maps to billing customer. |
| Membership | User role within workspace. |
| Subscription | Stripe customer/subscription/price state. |
| PlanEntitlement | Effective limits and features. |
| Project | QR project metadata and lifecycle state. |
| AssetVersion | Uploaded asset versions and storage metadata. |
| ProvisioningClaim | Crossplane claim name, namespace, status, archived/deactivated state, last error. |
| Domain | Custom domain verification and routing state. |
| UsageCounter | Views/scans/storage/events by billing period. |
| AuditLog | Security and admin trail. |

### AWS Organizations Feasibility

Creating individual AWS accounts for every customer via AWS Organizations is feasible but likely not appropriate for the low-cost tier because it adds account vending latency, quotas, billing complexity, support burden, guardrails, and cleanup complexity.

Recommended approach:

- Starter/Pro/Scale: use shared AWS account with strong tenant isolation through per-project private buckets/prefixes, IAM boundaries, tags, encryption, CDN private-origin controls, and application authorization.
- Maintain enough separation and metadata for investigations: per-workspace/project tagging, per-project storage prefixes or buckets, audit logs, upload provenance, and admin suspension controls.
- Enterprise: offer dedicated AWS account provisioning through AWS Organizations/Control Tower as an optional add-on.
- If account-per-customer is required, implement it asynchronously with a clear provisioning state machine: requested → account creating → baseline applying → ready → suspended → closing.

### diixtra-forge Platform Updates

QRBuddy will require platform-level changes outside this repo. These should live in `diixtra-forge` and be managed through GitOps where possible.

Required forge updates:

- Cloudflare DNS records for the initial `qr.diixtra.com` base URL.
- Cloudflare DNS zone/records for `qrbuddy.app` once the domain is purchased and delegated.
- DNS records for app hosting, API endpoints, CDN/CloudFront distributions, and auth callback URLs.
- Secrets and environment variables for app deployment: Better Auth, Stripe, database, email provider, Cloudflare, file scanning, and storage/provisioning integration.
- Deployment manifests for the QRBuddy web app, background workers, webhook handlers, and file scanning workers.
- Crossplane/XRD updates to support product-grade QR projects, including private bucket/origin settings, CDN distribution or shared distribution path mappings, cache policies, domain/base URL settings, archived/deactivated state, file type metadata, and potentially custom-domain resources.
- Flux sources/kustomizations or other release wiring for QRBuddy application environments.
- Monitoring/alerting resources for app health, provisioning health, file scanning failures, billing webhook failures, and DNS/custom-domain issues.

### Provisioning and Control Plane Scalability

The current approach assumes one control plane cluster and Flux/Crossplane managing all claims. This is acceptable for MVP, but scale planning is required if the product gains popularity.

Requirements:

- Design claim/provisioning integration so it can target multiple control plane instances in future.
- Track which control plane, namespace, and claim owns each project.
- Keep provisioning asynchronous and idempotent.
- Add capacity/health metrics for Flux reconciliation, Crossplane queue depth, failed claims, and provider API throttling.
- Consider a sharded control-plane model if needed: multiple Flux/Crossplane instances by region, customer segment, or load.
- Evaluate cloud-hosted workers/services such as Cloud Run for app-side orchestration, webhooks, file scanning, usage aggregation, and provisioning dispatch, while Crossplane remains responsible for infrastructure convergence.

## 9. Non-functional Requirements

| Category | Requirement |
|---|---|
| Security | Authenticated dashboard, secure sessions, CSRF/origin protections, least-privilege IAM, no unauthenticated upload endpoints. |
| Privacy | Clearly disclose public nature of QR assets; support deletion/export requests. |
| Reliability | Public QR URLs should target highly available object/CDN infrastructure. |
| Performance | QR target should load in under 1 second for cached image/PDF under normal conditions. |
| Cost efficiency | Public reads should be served from CDN/cache where possible; private object storage origin requests, origin egress, and invalidations should be minimized and monitored. |
| Scalability | Provisioning and usage tracking must be asynchronous and retryable; architecture must allow more control plane/Flux/Crossplane instances if demand grows. |
| Observability | Centralized logs, metrics, traces, and alerts for auth, billing, uploads, and provisioning. |
| Compliance | Stripe handles card data; app should avoid storing payment details. |
| Backup | Database backups and restore process required before paid launch. |

## 10. Success Metrics

| Metric | Target |
|---|---|
| Signup-to-first-QR completion | ≥ 60% of new signups create and download a QR code. |
| Time to first live QR | < 5 minutes median. |
| Upload replacement success rate | ≥ 99%. |
| QR target availability | ≥ 99.9% for paid tiers. |
| Free/Starter to Pro upgrade rate | Track baseline; target ≥ 5-10%. |
| Support tickets per 100 customers | Track and reduce with onboarding improvements. |

## 11. MVP Milestones

| Milestone | Scope |
|---|---|
| M1: Product foundation | Create web app, DB, Better Auth, workspace model. |
| M2: Project CRUD | Create project model, dashboard, upload UI, QR generation. |
| M3: Provisioning integration | App creates Crossplane claims and syncs status; forge contains required XRD/Composition/platform updates. |
| M4: Billing | Stripe checkout, webhook processing, plan enforcement. |
| M5: Production hardening | Logging, backups, admin panel, rate limits, deployment pipeline. |
| M6: Public launch | Landing/pricing pages, docs, support flow, monitoring. |

## 12. Decisions Captured and Remaining Questions

### Decisions Captured

1. Product positioning: general-use editable QR file hosting, with explicit inspiration for weddings, business menus, events, flyers, and similar use cases.
2. Public URLs: use standard URLs under a configurable domain; start with a `diixtra.com` subdomain until a product domain is purchased.
3. File types: support images and PDFs at launch.
4. File safety: include malware/file scanning for uploads before publication.
5. Limits: enforce configurable file count, max file size, and total storage limits.
6. Pricing: paid-only, no free tier/trial in MVP.
7. Initial self-serve tiers: £1.99/10 QR projects, £5.99/50 QR projects with custom domains, £9.99/100 QR projects with higher limits.
8. Custom domains: higher tiers only.
9. Branding/design: not MVP for custom landing pages, but product/brand assets should be created in `design-platform` and consumed by code.
10. Version retention: keep last 2 versions for 30 days.
11. Teams: shared asset/team access should exist, but all members need a paid account/seat.
12. Agency support: not MVP; backlog item.
13. Exceeding limits: block action with clear error and upgrade prompt; no overage behavior for MVP.
14. Inactive accounts/projects: public resources should be destroyed, with XRD/claim/project record archived or deactivated.
15. Isolation: shared infrastructure for self-serve tiers, with enough tagging/logging/separation for investigations; dedicated AWS accounts reserved for Enterprise.
16. Cost optimization: public S3 buckets should be replaced with private buckets/origins fronted by CloudFront or an equivalent CDN/cache layer.
17. Caching strategy: prefer immutable versioned asset keys and short-lived stable pointers over frequent paid CDN invalidations.

### Remaining Questions

1. What exact values should replace the tier storage placeholders: `STARTER_MAX_FILE_SIZE_MB`, `STARTER_TOTAL_STORAGE_MB`, `PRO_MAX_FILE_SIZE_MB`, `PRO_TOTAL_STORAGE_MB`, `SCALE_MAX_FILE_SIZE_MB`, and `SCALE_TOTAL_STORAGE_MB`?
2. Should scan/view limits be enforced in MVP, or only tracked initially?
3. Confirm domain ownership/DNS plan for `qrbuddy.app`.
4. Which email provider should be used for verification, password reset, billing notifications, and product emails?
5. Should ClamAV be run as an S3-triggered Lambda/container worker, a scheduled scanner, or a separate service? Should a managed scanning API be kept as fallback?
6. Should QR codes support styling/logo customization in MVP?
7. What exact capabilities are included in team seats at £9.99?
8. Which delivery provider should be used long term: AWS CloudFront/S3, Cloudflare/R2, Bunny, Backblaze B2 + CDN, or another hyperscaler/object-delivery option?
9. What default TTLs should be used for stable QR pointers/manifests and immutable asset versions?

## 13. Out of Scope for Initial MVP

- Dedicated AWS account per low-cost customer.
- SSO/SAML.
- Advanced QR styling editor.
- Complex page builder/custom branded landing page builder.
- White-label agency portals.
- Full compliance certifications.
- Native mobile apps.

## 14. Recommended Next Implementation Steps

1. Finalize placeholder tier variables for max file size, total storage, and scan/view tracking.
2. Use `qr.diixtra.com` as initial `PUBLIC_QR_BASE_DOMAIN`; migrate to `qrbuddy.app` when domain/DNS is ready.
3. Create design/brand assets in the `design-platform` repo for use-case inspiration and app UI.
4. Create a new web app package/repo structure rather than expanding only this infra claim repo.
5. Add Postgres schema for workspaces, projects, subscriptions, claims, usage, asset versions, and audit logs.
6. Implement Better Auth with organization/workspace support and paid-seat/team access rules.
7. Implement project creation that generates a Crossplane `XImageHosting` claim from app state.
8. Replace password-only upload with authenticated app-mediated pre-signed upload plus malware scanning before publication.
9. Add Stripe billing and entitlement enforcement before public launch.
10. Add required `diixtra-forge` infrastructure: Cloudflare DNS, app deployment manifests, secrets wiring, worker deployments, monitoring, and XRD/Composition updates.
11. Add a production delivery layer using private buckets/origins, a product-owned domain/subdomain, CDN caching, and versioned asset keys before custom domains.
12. Define the future multi-control-plane scaling model for Flux/Crossplane.
