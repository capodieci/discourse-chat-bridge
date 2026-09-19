# Server changes

Every infrastructure change to the production server is recorded here with the date, what changed, the exact commands used, and the exact commands to undo it.

## 2026-09-19, Phase 0

No changes. Phase 0 was read-only discovery. Nothing was installed, edited, restarted, or configured.

## 2026-09-19, RAM and disk resize

- What changed: Rob resized the VPS from 2 GB to 4 GB RAM, and added 20 GB of disk, taking the root filesystem from 58 G to 77 G.
- Performed by: Rob, at the provider. Not performed from this machine.
- Verified afterwards: 3.8 GB total RAM with 1.8 GB available, swap back to zero in use, 60 G free on `/`, container `app` up, `https://zoobc.pro/` returning HTTP 200.
- To undo: resize back at the provider. Not recommended. A rebuild with 44 plugins on 2 GB was the main risk in this project and this removes it.
