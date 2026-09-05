# Local development workflow

- After changing this application, restart the local development server yourself before reporting completion. The user has authorized routine server restarts; do not ask again.
- Start the server with `bin/dev -b 127.0.0.1 -p 3000` (or preserve the active port). This removes the precompiled asset manifest so Propshaft serves current source assets.
- Check that the process belongs to this project before stopping it. Use a full stop/start when changing server configuration or asset resolution; do not rely solely on `bin/rails restart`.
- Verify the affected page returns successfully over HTTP. For CSS/JavaScript changes, also fetch the asset URL referenced by that page and verify it contains the change. A passing Rails test alone does not prove the running server serves updated assets.
- If a browser is available, refresh the affected page and inspect it. If unavailable, report that limitation honestly; still complete the server and HTTP checks.
- Do not leave precompiled assets active in development after running asset build checks. Use `bin/rails assets:clobber` before restarting with `bin/dev` if needed.
