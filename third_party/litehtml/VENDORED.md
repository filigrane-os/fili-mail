# litehtml (vendored)

- Upstream: https://github.com/litehtml/litehtml, tag v0.9 (commit 6ca1ab0), BSD-3-Clause (LICENSE; gumbo, src/gumbo, Apache-2.0).
- Only `src/` and `include/` are kept; built by `build.rs` (no cmake).
- Local changes, all in `filigrane.patch` (already applied; `git apply` it on a fresh v0.9 checkout to update):
  - `media_query.cpp`: an unknown media feature such as `prefers-color-scheme` never matches (upstream applied
    the rule, so light mails turned dark); `and` and `only` are keywords, not media types (upstream, every
    `screen and (max-width: 600px)` query failed, so mobile layouts of mails never applied).
  - `render_block_context.cpp`: a table or other block formatting context that does not fit beside the floats
    moves below them (CSS 2.1 §9.5); upstream put it to the right of a full-width `align="left"` table, off the
    page, and Indeed mails rendered blank.
  - `render_table.cpp`: the `max-width` of a table limits its width (`width="100%" style="max-width:600px"` is the
    usual mail column; upstream ignored it and the mail filled the whole window).
  - `el_td.cpp`: the `cellpadding` of the table around gives its cells' padding (upstream kept the 1px default).
  - `render_block.cpp`: a `min-width` counts in the width a table cell measures for its content (upstream laid a
    `min-width:375px` button out in a cell a few pixels wide).

