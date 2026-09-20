# Posting notes for the announcement

The text to post is `announcement-post.md`, in this directory. It contains the post body and nothing else, so it can be pasted straight into a topic with no editing.

This file holds everything that is not the body: where it goes, what to call it, and what to attach.

## Category

meta.discourse.org has a **Plugin** subcategory under **Customization**, but it is a curated directory rather than somewhere community members can post. Attempting to create a topic there fails.

Post in **Marketplace** or **Dev** instead. Marketplace accepts free offerings as well as paid ones. Dev suits this particular post too, since much of it is about Discourse internals, and the API scope and rate limit findings are useful to that audience. Staff commonly move or index plugin topics afterwards, so posting somewhere reasonable and letting them sort it is normal practice.

## Title

Titles in that part of meta carry no prefix. The plugin name alone is the convention, as in "ActivityPub Plugin", "Discourse Affiliate", "Kanban Board".

- `Chat Bridge`
- `Chat Bridge: put your forum chat on your other websites`, if the category leans descriptive

## Tags

`chat`, `embed`, `cors`

## Images

Attach `images/widget.png` immediately after the opening two paragraphs. Meta topics do noticeably better with one image near the top. `images/admin.png` can go in the Installing section, or be left out.

## Two things to decide before posting

**Whether to say how it was built.** The post does not mention that it was written with an AI assistant. That is a deliberate omission rather than an oversight, and the decision belongs to whoever posts it.

**What a stranger will read in this repository.** Once the link is public, `CLAUDE.md` and `PROGRESS.md` are visible. Neither is embarrassing and `PROGRESS.md` documents the reasoning honestly, but both were written for the people building this rather than for an audience. Worth a look before the link goes out.

## The weakest claim in the post

The compatibility line. "Tested against 2026.9.0 and 2026.8.0, and in production use on one forum" is true, and one forum is a small number. The post says so plainly, which is the right way to handle it, but expect that to be the first thing anyone asks about.
