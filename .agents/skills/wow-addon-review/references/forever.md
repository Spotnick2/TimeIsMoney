# Forever client evidence

Treat API codebase and content rules as separate dimensions. This project targets
Vanilla-content Forever on Mainline UI APIs. Owner-supplied inventory:
C:\Projects\References\forever-api-1.60.1.70170.md (Interface 16001, WOW_PROJECT_ID 18).
Standalone compatibility target: Lua 5.1 and double arithmetic; confirm client runtime.

Read canonical C:\Projects\References\PORTING-TBC-TO-FOREVER.md and each finding's
measured build. The inventory proves names/signatures, not working behavior.
Do not apply TBC/Classic advice merely because the content resembles Vanilla.
Runtime observations belong in docs/forever-api-notes.md.

SavedVariables: initialize only after this addon's ADDON_LOADED. Test /reload
continuation and full client exit/relaunch. In-memory writes are not disk saves;
crashes/forced close can lose changes. Keep future schemas without overwriting.
The M0 scaffold does not initialize game saves.

Model evidence from AltStable 1.60.1.70124: plain ModelScene/CreateActor with
creature display ID; streamed bounding box yields six numbers, not just Retail's
two vectors. Keep bounded polls/tokens and fallback; goblin texture/crop/emotes
are unmeasured. See docs/MODELS.md. UI masks do not prove model/particle clipping.
