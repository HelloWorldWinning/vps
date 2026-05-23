# new_project

Refactored FastAPI file browser.

## Files

- `main.py` - FastAPI routes, authentication, directory listing, file serving.
- `css.txt` - all visual styles and font rules.
- `js.txt` - JavaScript entry point for later maintenance.
- `Dockerfile`, `docker-compose.yml`, `requirements.txt`, `build.sh` - deployment files.

## Font fix

Text-like files such as `.txt` are rendered through an HTML `<pre>` viewer by default, so `css.txt` controls the font with:

```css
html,
body,
html * {
    font-family: "SF Pro", -apple-system, BlinkMacSystemFont, "PingFang SC", "FZFangJunHeiS", sans-serif !important;
}
```

Use `?raw=1` on a file URL to return the original raw file response.
