# Shared Folder Panel

Internal notes on the Shared Folder panel (sidebar → Shared Folder → List): what it reads, the one file it writes, how the desktop app shows an entry in the file manager, and how it moves entries to the system's trash. The user-facing description is in `docs/basic-usage/web-interface.md` (section "Shared Folder Panel").

## Pieces

| Piece | File |
|---|---|
| Listing, protection reasons, root id | `docker/services/ruby/lib/monadic/workspace/shared_folder.rb` |
| Folder sizes (background count) | `docker/services/ruby/lib/monadic/workspace/shared_folder_sizes.rb` |
| HTTP routes (`GET /api/shared_folder`, `GET /api/shared_folder/sizes`, `GET /api/shared_folder/entry`) | `docker/services/ruby/lib/monadic/routes/shared_folder_routes.rb` |
| Page | `docker/services/ruby/public/js/monadic/shared-folder-panel.js` |
| "Show in file manager" and "Move to Trash" (Electron IPC `shared-folder-reveal`, `shared-folder-trash`) | `app/shared_folder_reveal.js`, `app/main.js`, `app/webview-preload.js` |

## Listing

Listing never changes a file (except `.monadic-shared-root`, below). What an entry is comes from the workspace ledger where the ledger records it (chat folders, public copies of attachments) and otherwise only from its name; a name is reported as a hint, never as proof that a file is unused. Links are listed as links and never followed.

`list` takes `query` (a substring of the name, any case), `classes` (classifications to keep), `sort` (`name`, `size` with the largest first and uncounted folders last, `modified` with the newest first) and `descending`. The name filter needs no look at the entries and runs first. Without a kind or an order other than name, only the page shown is described; otherwise every name left (up to `MAX_NAMES`) is described, then filtered, sorted and paged. Folder sizes are looked up (and queued for counting) for the order only when it is `size`, and for the page shown in any case. `matched` is the count after filtering, `total` the count of names read. `per_page` is at most 1000.

The page asks for one page at a time in any order. In size order the page asks for the list again once all counts it asked for are in, so the order shown is the order of the sizes. With `all: true`, `list` describes and returns every entry left (in any order, name order too) instead of one page; `matching` uses it with sizes as far as they are known (`Sizes#peek`, no count is queued).

Test files: a name starting with `SharedFolder::TEST_PREFIX` (`monadic-test-`, at any level) and the specs' scratch folder `.test_tmp` are classified `test_file`; names that specs used before (`TEST_CANDIDATE_PATTERNS`, and `TestApp_<digits>` under `auto_forge/`) are `test_candidate`. Specs name what they make in the user's shared folder with that prefix (`spec/support/shared_folder_test_files.rb`, which reads the same constant).

Entries that Monadic Chat or the user's own setup reads are protected (`SharedFolder::PROTECTED`): they are marked with a lock and a reason code that the page words in the UI language. When a new file or folder that Monadic Chat relies on is added to the top of the shared folder, add it to `PROTECTED` with a reason code, and add the code's wording to `ui.sharedFolderPanel` in `public/js/i18n/translations.js` (all UI languages).

## `.monadic-shared-root`

The panel's only write. A hidden file at the top of the shared folder holding 32 lowercase hexadecimal characters (`SecureRandom.hex(16)`).

**What it is for.** The page lists the folder as the Ruby server sees it (inside the container, `/monadic/data`); the desktop app opens entries in the folder it resolves on the host (`~/monadic/data`, or the WSL path on Windows). These are normally the same folder, but nothing guarantees it (a different data path, a second installation, a WSL distribution with its own home). The id ties the two: the page sends the id with each request, and the desktop app acts only when the id file in the folder it resolved holds the same id. Without it, a relative path could name an entry in a different folder.

**How it is made.** `SharedFolder.root_id` creates it the first time the id is asked for (the first listing):

1. The id is written to a temporary file of its own (`.monadic-shared-root.<random>`, opened with `O_EXCL`).
2. The temporary file is hard-linked to `.monadic-shared-root`, so no reader sees a file that is still empty, and when two first requests race, one link wins and both read the same id (`Errno::EEXIST` is the loser's normal path).
3. The temporary file is removed.

The file must be a plain file (`lstat`, not a link) holding exactly 32 hexadecimal characters; anything else is reported as the reason the id is missing. When the id cannot be made (for example, a read-only folder), the list is still shown; only "Show in file manager" is unavailable.

**Lifecycle.**

- It is never rewritten. Deleting it makes a new id on the next listing; a page listed before that sends the old id, and the desktop app refuses until the page is listed again.
- It is protected in the panel (`folder_id`), so it is never offered for removal.
- It belongs to the folder, not to an installation: restoring the shared folder from a backup brings its id along, which is the intended behaviour.
- It holds no secret. It is an identity check between two views of the same folder, not an access control; the IPC checks below are what limit the reveal.

**Where it is documented for users.** `docs/basic-usage/web-interface.md` and `docs/ja/basic-usage/web-interface.md` ask users not to delete it. Keep that sentence when the section is edited.

## "Show in file manager"

`createRevealHandler` in `app/shared_folder_reveal.js` accepts a request only when:

- it comes from the main frame of the window the app opened for its pages (`isAppSender`), not only from a page at the app's address;
- that frame shows the app's page itself (path `APP_PAGE_PATH`, `/`): files of the shared folder are served at the same address (`/data/...`, `/monadic/data/...`) and get the same preload API;
- the path is relative, with no empty, `.` or `..` part, and no part that the platform would read as something else (`sharedPathParts`);
- the root id has the 32-hexadecimal form and matches the id file in the folder the app resolved;
- no part of the path, at any level, is a link.
- each part is spelled as its folder lists it (a system that ignores case would otherwise find another spelling).

The shared folder itself is opened in the file manager; every other entry, a folder too, is shown selected in its parent (`shell.showItemInFolder`), never opened or run (a folder can be one the system opens as an app, such as `Name.app` on macOS).

## "Move to Trash"

An entry may be moved to the trash (`capabilities.trash`) when it is a file or folder, not protected (nor inside a protected entry), and not in use: the folder of a chat open in a tab, what is in it, and the playback copy of that chat's attachment are in use (`busy_reason`). The listing gives it only when the folder id is there, as for "Show in file manager".

`createTrashHandler` in `app/shared_folder_reveal.js` takes up to `MAX_TRASH` relative paths and, for each, applies the same checks as the reveal (sender, path form, folder id, no link at any level, each part spelled as the folder spells it: on macOS when `fs.realpathSync.native` of the entry is the shared folder's real path joined with the parts as asked, otherwise, and on other systems, by listing each folder on the way), then asks the server (`GET /api/shared_folder/entry`, from `askSharedEntry` in `app/main.js`, 10 s; an answer that cannot be read means not removed, and when the server cannot be reached at all (`NO_ANSWER`) that entry is not removed and the rest are returned with `not_tried`) and moves the entry with `shell.trashItem` only when the server says it may go and the server's kind (file or folder) is the kind the desktop app sees; just before the move, the shared folder must still be the same folder (`dev`/`ino`) with the same id file, and the entry the same entry (`dev`/`ino`) with no link on the way. The server refuses a path not spelled as the folder lists it, the folders Monadic Chat keeps at the top for a purpose (`SharedFolder::FOLDERS`, such as `conversations`), any folder holding the folder of a chat open in a tab, and every entry while the ledger cannot be read. These checks are separate operations: a change made by another local process between the last check and `shell.trashItem`, or a chat opened after the server answered, is not prevented. The answer lists each path with `ok` and, when not moved, the reason. Before any entry is checked against the server, the desktop app shows a dialog of its own (`confirmSharedTrash` in `app/main.js`: the count and the first five paths, Cancel by default); nothing is moved unless the person agrees there, and a handler without `confirm` moves nothing. The page cannot answer the dialog. When it is cancelled the handler returns `cancelled: true` and the page keeps the list and the choice; otherwise the page lists the folder again if it still shows the folder the run started in, keeps chosen what was not moved, and shows the counts moved, not moved and not tried, with every entry not moved in a list that opens, in the status line (`#shared-folder-status`). One run at a time: while a run is under way (the dialog included) a spinner covers the panel (`#shared-folder-busy`), the rest of the panel is `inert`, and `hide.bs.modal` is prevented. "Skip folders when selecting all" (`#shared-folder-files-only`, kept in local storage) makes "Select all shown", "Select on all pages" and Cmd/Ctrl+A skip folders.

## Preview

`Monadic::Workspace::SharedFolderPreview` (`lib/monadic/workspace/shared_folder_preview.rb`) holds the extension table (`MEDIA`, `TEXT`); the listing gives each file its `preview` kind from it, and the routes check the kind again. HTML, SVG and XML are text: they are never sent as their own type.

- `GET /api/shared_folder/text`: the first `TEXT_LIMIT` bytes as UTF-8 JSON (`text`, `truncated`, `file_bytes`, `shown_bytes`); a NUL byte in what was read gives 415. The page puts the text in a `<pre>` with `textContent`.
- `GET /api/shared_folder/file`: images, audio, video and PDFs, with one byte range (`bytes=a-b`, `a-`, `-n`; another unit, several ranges or an invalid one send the whole file; past the end gives 416). Media other than PDF get `Content-Security-Policy: sandbox; default-src 'none'`; a PDF gets `frame-ancestors 'self'` and `X-Frame-Options: SAMEORIGIN` (the browser's viewer does not open in a sandbox).
- Both refuse (403) any request whose `Sec-Fetch-Site` is not `same-origin`, a request without it included, before looking anything up, and send `Cross-Origin-Resource-Policy: same-origin`, `Cache-Control: no-store` and `nosniff`.
- `open_file` checks each part's spelling against the folder, refuses a link on the way (`folder_at`) and at the end (`O_NOFOLLOW`), opens with `O_NONBLOCK` (a FIFO does not hold it), then asks the system where the open file is (`/proc/self/fd` on Linux, `F_GETPATH` on macOS) and refuses it unless that is the path checked: a folder swapped for a link after the check would lead elsewhere. Where the system cannot tell, the file is closed unread and nothing is sent (501). The two paths are compared as bytes. The file sent is the one opened (`FileBody`), closed when the response ends.

Pages and choosing all: the panel asks for one page at a time (`page`, `per_page` 100, 200 or 500, kept in local storage) in any order. `GET /api/shared_folder/matching` gives every entry matching the search, kinds and age that may be moved to the trash (`SharedFolder.matching`, from the first `MAX_NAMES` names), for "Select on all pages". The desktop app moves up to `MAX_TRASH` entries after one dialog; it equals `MAX_NAMES` (checked by `test/frontend/shared-folder-trash.test.js`), and repeated paths are refused.

Age filter: `older_than_days` (30, 90 or 365) keeps entries modified more than that many days of 86,400 seconds before the request; it takes the listing's slow path, as a kind filter does.

## Folder sizes

Sizes are counted in the background with one shared budget per pass. Each folder's result carries a status (complete, partial, changed while counted, failed), and a complete count is never replaced by a partial one. Only plain folders under the shared folder's real path are counted (`plain_folder?`); links are not followed.

Layout: an upper band of search and filters (`.sf-conditions`) and, where entries can be moved to the Trash, a lower band of selecting and the trash button (`#shared-folder-actions`). Its buttons have fixed labels and are disabled, never hidden, when they have nothing to act on; what is selected is shown beside them in a fixed width (`.sf-choice-info`), so no button moves. One status line below the bands (`#shared-folder-status`, `role="status"`) shows loading (after 250 ms), an empty folder, nothing matching, errors and the result of moving to the Trash; the table body has `aria-busy` while a list is loading.
