# Decision records

Short records: context, decision, consequences.

## 0001: Hosting the bridge over HTTPS

- Date: 2026-09-19
- Status: proposed, awaiting Rob
- Context: the Discourse container binds host ports 80 and 443 directly. There is no web server and no PHP on the host. Cloudflare proxying is already active on the domain. The brief offered plan A, an outer web server with Discourse moved behind a socket, requiring a rebuild, and plan B, a separate port, objecting that non-standard ports are blocked on some networks and that certificates cannot be issued over port 80.
- Decision: neither as written. Use Cloudflare to proxy `chat.zoobc.pro` on standard 443 at the edge to a non-standard origin port on this host, with a Cloudflare Origin Certificate on the origin.
- Consequences: visitors always use port 443, so the plan B objection does not apply. No Let's Encrypt and no renewal machinery, because an Origin Certificate lasts 15 years. Discourse is not touched: no app.yml change, no rebuild, no downtime. The origin port is firewalled to Cloudflare ranges only. The cost is a hard dependency on Cloudflare remaining in front of the domain.

## 0002: Plugin versus external bridge

- Date: 2026-09-19
- Status: open, awaiting Rob
- Context: see sections 5, 6, 7 and 13 of `docs/discovery-report.md`. The installed source shows only one granular chat API scope, chat webhooks covering only four message events, and API rate limit buckets of 60 and 20 requests per minute.
- Decision: pending.
- Consequences: pending.
