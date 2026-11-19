# After cutover — what you need to do

Replace `<Company>`, `<help desk>` and `<new sign-in>` before sending this to users.
The list is in the order you do things — day 1 first, then the first week.

## Day 1 — getting in

1. **Sign in on the new PC** with your new account `<new sign-in>`.
   Your old PC is untouched — leave it alone for now.
2. **Outlook — create a new profile.** Don't reuse the old profile; it points at
   the old tenant. If Outlook offers your old account, remove it and add the new one.
   The first open can take a while while mail downloads.
3. **OneDrive** — sign in with the new account. If Known Folder Move is offered,
   accept it to sync Desktop/Documents/Pictures.
   Old shared links still open via a redirect — update your bookmarks when you can.
4. **Teams** — sign out of the old work account everywhere, sign in with the new one.
5. **Mobile apps** (Outlook, Teams, OneDrive) — remove the old work account,
   add the new one.
6. **Browser bookmarks and saved links** pointing at the old tenant — replace them
   with links to the new tenant. OneDrive/SharePoint links redirect for now, but not
   forever.

## First week — check these

7. **Outlook signatures** — recreate them; they don't migrate.
8. **Delegates and Send on Behalf** — if you share your calendar or send on behalf of
   others, check that it still works and tell `<help desk>` if it doesn't.
9. **Shared mailboxes** — they should appear in Outlook automatically after the
   permissions are restored. If one is missing, add it manually or report it.
10. **Meetings — re-accept them.** Meeting acceptances (RSVPs) were reset during the
    move — open your calendar and accept the meetings you plan to attend.
11. **Organisers:** if you edited a single occurrence of a meeting series, that
    occurrence keeps an old link — re-send the series to everyone.
12. Meetings with **external guests** may need a fresh invitation (check your
    migration notice for the answer for this tenant pair).
13. **Channel meetings, webinars and live events must be recreated** — they didn't
    move. Same for meetings organised by a room mailbox.
14. **Meeting recordings, transcripts and attendance reports stay in the old
    tenant** — download anything you still need before it's gone.
15. **Teams chats** — your chats came across as new threads. You may see some
    duplicates or temporary-looking chats; chat-with-self, reactions, apps and
    polls are gone.
16. **The Teams calendar in the old tenant no longer works** — use the new account.
17. **Files that lived only on your old PC** (outside OneDrive/Desktop/Documents/
    Pictures) — copy what you need before the old PC is wiped.

## Changes you will notice

- Sign-ins, MFA prompts and "new device" e-mails — expected on day 1.
- Some chat threads appear twice or with a placeholder name — cosmetic.
- Old links to files may redirect for a while, then stop — update them.
- Anything IT said doesn't migrate is listed for them in
  `docs/What-Doesnt-Move.md` — ask `<help desk>`, not the old PC's settings.

## Something wrong?

Contact `<help desk>`. Tell them your old PC is untouched — most things can be
re-checked against it while it still exists.
