# Architecture decision records

Each file records one decision: the context, what we decided, and what follows from it. The [FABA design document](../faba-design-document.md) explains the full design. These records are the short, stable answer to "why is it like this?"

## Index

| ADR                                                       | Decision                                                                   | Status                       |
| --------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------- |
| [001](001-server-output-with-prerendered-public-pages.md) | `output: 'server'`, with public pages prerendered                          | Accepted                     |
| [002](002-single-cloudflare-worker.md)                    | A single Cloudflare Worker hosts the Astro app                             | Accepted                     |
| [003](003-server-only-supabase-access.md)                 | Server-only Supabase access with the user's JWT                            | Accepted                     |
| [004](004-writes-through-definer-rpc.md)                  | Writes to rule-bearing tables go through `SECURITY DEFINER` functions      | Accepted                     |
| [005](005-eligibility-gate.md)                            | Four-layer `byui.edu` eligibility gate; roles read from the database       | Accepted                     |
| [006](006-pg-cron-for-data-jobs.md)                       | `pg_cron` for data jobs; Cloudflare Cron and Queues only for delivery      | Accepted                     |
| [007](007-notification-model.md)                          | Per-recipient notification rows, one creation path                         | Accepted                     |
| [008](008-denormalized-rsvp-counts.md)                    | RSVP counts maintained only by `rsvp()`, reconciled nightly                | Accepted                     |
| [009](009-previews-share-staging-database.md)             | Previews share the staging database                                        | Accepted, revisit at Phase 3 |
| [010](010-rsvp-and-moderation-in-phase-1.md)              | Basic RSVP and minimal moderation move into Phase 1                        | Accepted                     |
| [011](011-no-ui-framework-by-default.md)                  | No UI framework by default                                                 | Accepted                     |
| [012](012-github-actions-for-ci-cd.md)                    | GitHub Actions for CI/CD                                                   | Accepted                     |
| [013](013-synthetic-staging-pilot-in-production.md)       | Staging holds only synthetic data; the pilot runs in production            | Accepted                     |
| [014](014-cloudflare-and-supabase-stack.md)               | Replace the Node adapter and Compose Postgres with Cloudflare and Supabase | Accepted                     |
| [015](015-any-byui-account-can-join.md)                   | Any `byui.edu` account can join; no faculty attestation                    | Accepted                     |
| [016](016-independent-of-byu-idaho.md)                    | FABA runs independently of BYU-Idaho                                       | Accepted                     |
| [017](017-rexburg-only-for-now.md)                        | Phase 1 serves in-person Rexburg activities only                           | Accepted                     |

ADRs 001 to 013 come from section 13.2 of the design document. ADRs 014 to 017 record the Phase 0 answers to its [unresolved questions](../faba-design-document.md#unresolved-questions-to-answer-before-development) (FND-02).

## Adding or changing a decision

1. Copy [template.md](template.md) to the next number, such as `018-short-title.md`.
2. Fill it in and open a pull request. Use the status **Proposed** until the decision is agreed, then **Accepted**.
3. Add a row to the index above and to section 13.2 of the design document.
4. Don't rewrite an accepted ADR to change the decision. Write a new one, mark the old one **Superseded by ADR-NNN**, and link both ways.
