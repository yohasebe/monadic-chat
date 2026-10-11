# Shared Folder Panel

Internal notes on the Shared Folder panel (sidebar → Shared Folder → List): what it reads, the one file it writes, and how the desktop app shows an entry in the file manager. The user-facing description is in `docs/basic-usage/web-interface.md` (section "Shared Folder Panel").

## Pieces

| Piece | File |
|---|---|
| Listing, protection reasons, root id | `docker/services/ruby/lib/monadic/workspace/shared_folder.rb` |
| Folder sizes (background count) | `docker/services/ruby/lib/monadic/workspace/shared_folder_sizes.rb` |
| HTTP routes (`GET /api/shared_folder`, `GET /api/shared_folder/sizes`) | `docker/services/ruby/lib/monadic/routes/shared_folder_routes.rb` |
| Page | `docker/services/ruby/public/js/monadic/shared-folder-panel.js` |
| "Show in file manager" (Electron IPC `shared-folder-reveal`) | `app/shared_folder_reveal.js`, `app/main.js`, `app/webview-preload.js` |

## Read only, except for one file

Listing never changes a file. What an entry is comes from the workspace ledger where the ledger records it (chat folders, public copies of attachments) and otherwise only from its name; a name is reported as a hint, never as proof that a file is unused. Links are listed as links and never followed.

Entries that Monadic Chat or the user's own setup reads are protected (`SharedFolder::PROTECTED`): they are marked with a lock and a reason code that the page words in the UI language. When a new file or folder that Monadic Chat relies on is added to the top of the shared folder, add it to `PROTECTED` with a reason code, and add the code's wording to `ui.sharedFolderPanel` in `public/js/i18n/translations.js` (all UI languages).

## `.monadic-shared-root`

The panel's only write. A hidden file at the top of the shared folder holding 32 lowercase hexadecimal characters (`SecureRandom.hex(16)`).

**Why it exists.** The page lists the folder as the Ruby server sees it (inside the container, `/monadic/data`); the desktop app opens entries in the folder it resolves on the host (`~/monadic/data`, or the WSL path on Windows). These are normally the same folder, but nothing guarantees it (a different data path, a second installation, a WSL distribution with its own home). The id ties the two: the page sends the id with each request, and the desktop app acts only when the id file in the folder it resolved holds the same id. Without it, a relative path could name an entry in a different folder.

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
- the path is relative, with no empty, `.` or `..` part, and no part that the platform would read as something else (`sharedPathParts`);
- the root id has the 32-hexadecimal form and matches the id file in the folder the app resolved;
- no part of the path, at any level, is a link.

A folder is opened in the file manager; a file is shown selected in its folder (`shell.showItemInFolder`), never opened or run.

## Folder sizes

Sizes are counted in the background with one shared budget per pass. Each folder's result carries a status (complete, partial, changed while counted, failed), and a complete count is never replaced by a partial one. Only plain folders under the shared folder's real path are counted (`plain_folder?`); links are not followed.
