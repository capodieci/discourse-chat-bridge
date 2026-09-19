# Conventions for this repository

## Working style

- Ask when something is ambiguous or a decision has real consequences. Do not assume.
- Explain what you are about to do and why, in plain language, before doing it.
- Never use placeholders in code such as "rest of the code here" or "existing code unchanged". Every file must be complete and runnable.
- Do not use the em dash character in documentation or messages. Use commas, colons, or periods.
- Bullet lists for technical documents, prose for letters and announcements.
- Domain modeling first: update `docs/domain-model.md` before writing code for a phase.
- At the end of every phase: update `PROGRESS.md`, commit, and stop for review.

## Technical preferences

- No Node.js on the server, no React, no Vue, no build step, no bundler, no TypeScript.
- The widget is vanilla JavaScript, served as one file, embedded with one script tag.
- Avoid dependency managers. Ask before adding any dependency, and explain why.
- Prefer many small independent programs sharing data through the database, files, or pipes, over one large class.
- Never build SQL by string concatenation. Prepared statements only.
- JSON in by POST, JSON out. Avoid GET except for static files and redirects.

Language choice is settled per phase in `docs/decisions.md`, based on what the installed Discourse source actually supports.

## Safety rules for the production server

1. Never run `./launcher rebuild`, `./launcher destroy`, `./launcher cleanup`, `docker rm`, or `docker system prune` without Rob's explicit yes in the same session for that specific command.
2. Before any change to Discourse configuration or the container definition: take a backup and confirm the file exists, copy `app.yml` to a timestamped backup, check free disk and RAM.
3. Every infrastructure change is recorded in `docs/server-changes.md` with date, what changed, exact commands used, and exact commands to undo it.
4. Never print secrets: API keys, database passwords, SMTP passwords, env section contents. Redact when reporting.
5. Never commit secrets. Config with secrets lives outside the repository and outside the web root, mode 0600, owned by the service user.
6. Never modify forum data directly in PostgreSQL. Writes go through the HTTP API or through reviewed `rails runner` scripts.
7. Do not open new firewall ports without asking.
8. If anything unexpected happens to the forum, stop all work, report, and propose a rollback.

Host note: check free memory before starting a Rails process inside the container. `rails runner` loads the whole application and can push a small instance into an out of memory condition while the forum is live. Reading source files and querying Postgres directly costs almost nothing and answers most questions. On a host with a gigabyte or less free, prefer them.
