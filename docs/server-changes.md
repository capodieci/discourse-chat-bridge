# Server changes

Every infrastructure change to the production server is recorded here with the date, what changed, the exact commands used, and the exact commands to undo it.

## 2026-09-19, Phase 0

No changes. Phase 0 was read-only discovery. Nothing was installed, edited, restarted, or configured.

## 2026-09-19, RAM and disk resize

- What changed: Rob resized the VPS from 2 GB to 4 GB RAM, and added 20 GB of disk, taking the root filesystem from 58 G to 77 G.
- Performed by: Rob, at the provider. Not performed from this machine.
- Verified afterwards: 3.8 GB total RAM with 1.8 GB available, swap back to zero in use, 60 G free on `/`, container `app` up, `https://zoobc.pro/` returning HTTP 200.
- To undo: resize back at the provider. Not recommended. A rebuild with 44 plugins on 2 GB was the main risk in this project and this removes it.

## 2026-09-19, plugin install and CORS enable

- Backup taken first and verified: `gzip -t` passes, archive contains `dump.sql.gz` and the uploads tree.
- `app.yml` copied to `/var/discourse/containers/app.yml.bak-20260919-154033`.
- Two additions to `app.yml`, confirmed by diff, nothing else touched:
  - `DISCOURSE_ENABLE_CORS: true` appended to the existing `env` block
  - a new `hooks:` section with an `after_code` exec cloning the plugin into `$home/plugins`
- Command run: `cd /var/discourse && ./launcher rebuild app`
- Site settings applied afterwards through `rails runner`: `chat_bridge_enabled = true`, `cors_origins = https://zoobc.com|https://zoobc.foundation`
- Two sites registered with `rake chat_bridge:site:add`.

Verified afterwards: homepage, `/latest`, `/login`, `/chat` and `/about` all return 200. Forum data intact at 8 users, 319 posts, 261 topics, both chat channels present. The three plugin tables exist. `GET /chat-bridge/health` returns 200.

### Side effect that was not anticipated

`./launcher rebuild` pulls the latest Discourse image, so the forum was upgraded from `2026.8.0-latest.1` to `2026.9.0-latest` as part of this operation. That was not called out before the rebuild was approved, and it should have been. The upgrade appears clean and the findings in the discovery report were re-checked against the new version and still hold: four chat webhook event types, one granular chat API scope.

### To undo

```
sudo cp /var/discourse/containers/app.yml.bak-20260919-154033 /var/discourse/containers/app.yml
cd /var/discourse && sudo ./launcher rebuild app
```

That removes the plugin and disables CORS. It does not downgrade Discourse, because the image is already pulled. The plugin's three tables would be left behind, holding no forum data, and can be dropped separately if wanted.

## 2026-09-19, backup retention loss

- What happened: the backup command was run three times in quick succession, the second while the first was still running. Each successful run triggers Discourse's retention pass, and `maximum_backups` is 5.
- Consequence: the backups from 17, 24 and 31 August were pruned. Remaining: 7 September, 14 September, and three identical copies from 19 September.
- Cause: operator error, running the command again instead of waiting for the background run to finish.
- Suggested remedy, not yet applied: delete two of the three 19 September duplicates so the retention window is not consumed by copies of the same snapshot.

## 2026-09-19, backup cleanup and third site

- Deleted two duplicate backups from 19 September, `154039` and `154127`, with Rob's approval. Kept `154209`, the last snapshot taken before the rebuild, verified intact beforehand with `gzip -t` and a listing of its 49 entries.
- Backups now: 7 September, 14 September, 19 September. Three of five retention slots used, so the next two weekly backups will not push out 7 September.
- To undo: not possible, the files are gone. The remaining 19 September backup is byte for byte a backup of the same moment, so nothing unique was lost.
- Registered `https://zoobc.network` as the third embedding site. `cors_origins` is now `https://zoobc.com|https://zoobc.foundation|https://zoobc.network`.
- Verified by live request that each of the three origins is reflected back to itself, and that an unregistered origin is not.
- `https://zoobc.net` is planned but not added.
