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
----------------------------
More points

Yes — there are several operational and platform-engineering advantages of using Teams that become very important as Grafana adoption grows.

Here are the strongest additional arguments.

1. Lower Operational Overhead

With Teams:

one Org to manage
one provisioning flow
one RBAC model
one alerting environment
one backup strategy

With Orgs:

repeated setup per org
repeated permission management
repeated troubleshooting

Every new Org becomes another mini-Grafana deployment operationally.

2. Easier Infrastructure-as-Code (Terraform/Provisioning)

Using Teams keeps:

dashboards reusable
provisioning paths consistent
folder structures standardized

With Orgs:

resources must often be duplicated
automation needs org awareness
imports/exports become messy
UID conflicts become common

Terraform complexity grows significantly with multiple orgs.

3. Easier Onboarding

With Teams:

add user to Team
done

With Orgs:

assign org role
explain org switching
duplicate memberships
handle “wrong org” confusion

New users regularly get confused by Org context switching.

4. Better User Experience

Teams provide:

seamless navigation
shared search
unified dashboard discovery
shared alert visibility

Orgs create silos:

users cannot easily discover useful dashboards
duplicate dashboards appear
collaboration decreases

You lose the “shared observability platform” effect.

5. Avoid Dashboard Duplication

This becomes a major pain later.

Example:

shared Kubernetes dashboards
shared platform dashboards
shared infra dashboards

With Teams:

reuse once

With Orgs:

copy to every org
maintain separately
versions drift over time

This becomes a maintenance nightmare.

6. Easier Standardization

Teams allow:

common dashboard standards
shared variables
common alerting patterns
shared naming conventions

Orgs encourage fragmentation:

each org invents its own structure
inconsistent observability practices emerge

Platform governance becomes harder.

7. Easier Cross-Team Troubleshooting

Real incidents usually cross boundaries:

networking
Kubernetes
databases
applications
platform services

With Teams:

everyone can collaborate quickly

With Orgs:

observability becomes siloed
troubleshooting slows down

Incident response suffers.

8. Alerting Is Simpler

Unified alerting works better with Teams:

centralized routing
shared contact points
reusable templates

With Orgs:

duplicated alert definitions
duplicated notification channels
duplicated silences/escalations

Operational noise increases.

9. Resource Efficiency

Organizations encourage:

duplicated datasources
duplicated folders
duplicated alerts
duplicated dashboards

Teams encourage reuse.

This matters a lot at scale.

10. Better for Internal Platform Culture

Teams support:

“Grafana is a shared engineering platform.”

Orgs support:

“Every group is its own tenant.”

For internal engineering organizations, the first model usually creates better collaboration and maturity.

11. Orgs Are Often a Legacy Pattern

Historically many people used Orgs because:

folder permissions were weaker
Teams were less mature
old Grafana versions lacked features

Modern Grafana usage trends toward:

single Org
Teams
folders
RBAC

especially for internal platforms.

12. Easier Migration Later

Moving:

Teams → Orgs later is possible

Moving:

Many Orgs → unified Teams later is painful

Starting simple is strategically safer.

13. Plugin and Upgrade Management Is Cleaner

Even with Orgs:

plugins are mostly instance-wide
upgrades are instance-wide
outages are instance-wide

So Orgs do not provide true infrastructure isolation anyway.

You pay operational cost without full tenant isolation.

14. Reduces “Shadow Observability”

When teams get isolated Orgs:

they often create duplicated dashboards
duplicated metrics
inconsistent alerts
custom hacks

Shared Teams environments naturally encourage reuse and consistency.

15. Easier Global Search and Discoverability

With Teams:

users can search shared dashboards
platform dashboards become reusable
best practices spread organically

With Orgs:

knowledge gets trapped inside silos

This hurts observability maturity over time.

Short Executive-Level Argument

You can summarize it like this:

Organizations solve tenant isolation.
Teams solve collaboration and operational scalability.

If your company is not offering Grafana as a customer-facing multi-tenant SaaS platform, Teams are usually the better engineering choice.

Or even shorter:

Use Orgs for isolation between companies.
Use Teams for isolation between internal engineering groups.
