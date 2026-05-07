Grafana Isolation Decision Questionnaire

Use this with your teammate to objectively decide between Teams and Organizations in Grafana Open Source
.

The key principle:

Teams = authorization grouping inside one tenant
Organizations = separate tenants

Most internal multi-team setups are not actually multi-tenant systems.

Decision Questionnaire
1. Do teams require completely separate login/admin boundaries?
If YES

→ Prefer Organizations

If NO

→ Prefer Teams

Why

Organizations are designed for tenant isolation.
Teams are designed for collaboration within one Grafana environment.

2. Do users need access to dashboards across multiple teams?
If YES

→ Prefer Teams

Why

Users can belong to multiple teams easily.

With Orgs:

users must switch org context
dashboards cannot be shared naturally
duplication becomes common

This becomes painful very quickly.

3. Will platform/admin teams need centralized visibility and management?
If YES

→ Prefer Teams

Why

Single-org operations are much simpler:

one place for users
one alerting setup
one plugin management flow
one provisioning workflow
easier Terraform/automation
simpler backups

With Orgs:

every resource becomes duplicated
provisioning complexity grows linearly
4. Do teams need different plugins or Grafana settings?
If YES

→ Prefer Organizations

Caveat

In OSS many settings/plugins are still instance-wide, so Orgs are not full isolation anyway.

If true tenant isolation is required, separate Grafana instances may actually be better than Orgs.

5. Is the concern mainly:

“We don't want teams editing each other's dashboards”

If YES

→ Prefer Teams

Why

Folders + permissions already solve this cleanly.

Typical model:

Team A folder
Team B folder
Editor rights scoped per folder

No Org needed.

6. Is the concern:

“We don't want teams even seeing each other's datasources”

If YES

→ In OSS this is the strongest argument for Organizations

Important nuance

This is not really a “Teams vs Orgs” issue.

This is an OSS limitation:

datasource permissions are weak in OSS
Enterprise handles this much better

Ask:

Is datasource secrecy actually required?
Or only dashboard separation?

Many teams over-engineer isolation here.

7. Will dashboards/templates/alerts be reused across teams?
If YES

→ Prefer Teams

Why

Reuse becomes dramatically easier in one Org.

With Orgs:

duplication everywhere
export/import cycles
drift between orgs
8. Do you expect more teams over time?
If YES

→ Prefer Teams

Why

Scaling Orgs operationally becomes expensive:

more provisioning
more RBAC management
more automation complexity
more drift
more troubleshooting

Teams scale much more naturally.

9. Are these internal engineering teams under the same company/platform governance?
If YES

→ Prefer Teams

Why

That is exactly the intended use case for Teams.

Organizations fit:

external customers
managed service tenants
business-unit isolation
compliance boundaries
10. Would separate Grafana instances actually solve the problem better than Orgs?
If YES

→ Orgs may be the wrong abstraction entirely

Why

Orgs often become “fake multi-tenancy”:

still shared infrastructure
shared upgrades
shared outages
shared plugins

If isolation is truly critical:

separate instances are cleaner
Summary Matrix
Requirement	Teams	Orgs
Simple operations	✅	❌
Shared dashboards	✅	❌
Users in multiple groups	✅	❌
Centralized management	✅	❌
Folder-level separation	✅	⚠️ Overkill
Strong datasource isolation	❌ OSS limitation	✅
Multi-tenant setup	❌	✅
External customer isolation	❌	✅
Scalability/admin simplicity	✅	❌
Strong Technical Argument for Teams

Your teammate is likely optimizing for:

“Isolation sounds safer.”

But in practice with Grafana OSS:

Orgs introduce:
duplicated configuration
duplicated dashboards
duplicated alerting
duplicated provisioning
context switching
operational overhead
automation complexity
inconsistent standards

while often providing only partial isolation.

A Good Compromise Architecture

A very common mature setup is:

Default
Single Org
Teams
Folder permissions
Exceptional cases

Use separate Org only for:

external tenants
regulated environments
highly sensitive datasource separation

This avoids turning Grafana administration into a multi-tenant platform problem unnecessarily.
