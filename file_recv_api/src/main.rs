use axum::{
    Router,
    extract::{DefaultBodyLimit, Multipart, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
};
use chrono::{Datelike, Utc};
use chrono_tz::Tz;
use std::{
    collections::HashSet,
    env,
    net::SocketAddr,
    path::{Path, PathBuf},
};
use tokio::{
    fs::{self, File},
    io::AsyncWriteExt,
};
use tracing::{error, info};
use tracing_subscriber::{EnvFilter, fmt};

#[derive(Clone)]
struct AppState {
    base_path: PathBuf,
    allowed_exts: HashSet<String>,
    api_passwd: String,
    tz: Tz,
}

#[derive(Debug)]
struct BadRequest(&'static str);

impl IntoResponse for BadRequest {
    fn into_response(self) -> Response {
        (StatusCode::BAD_REQUEST, self.0).into_response()
    }
}

#[derive(Debug)]
struct Unauthorized;

impl IntoResponse for Unauthorized {
    fn into_response(self) -> Response {
        (StatusCode::UNAUTHORIZED, "unauthorized").into_response()
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Logging
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    fmt::Subscriber::builder()
        .with_env_filter(env_filter)
        .init();

    // Required: API_PASSWD (fail fast if not set)
    let api_passwd =
        env::var("API_PASSWD").expect("Missing env var API_PASSWD (e.g., API_PASSWD=kkb)");

    // Optional: TIMEZONE (default Asia/Shanghai)
    let tz_str = env::var("TIMEZONE").unwrap_or_else(|_| "Asia/Shanghai".to_string());
    let tz: Tz = tz_str.parse().unwrap_or_else(|_| {
        eprintln!(
            "WARN: TIMEZONE='{}' not recognized. Falling back to Asia/Shanghai.",
            tz_str
        );
        chrono_tz::Asia::Shanghai
    });

    // Optional: SAVING_PATH (default /saving_path)
    let base_path =
        PathBuf::from(env::var("SAVING_PATH").unwrap_or_else(|_| "/saving_path".into()));

    // Optional: PORT (default 7778)
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(7778);

    // Optional: FILE-TYPES-EXTENTION (default txt,md,py,rs)
    // NOTE: uses the **exact** hyphenated name from your docker-compose.yml.
    let default_exts = "txt,md,py,rs".to_string();
    let allowed_exts_raw =
        env::var("FILE-TYPES-EXTENTION").unwrap_or_else(|_| default_exts.clone());

    let allowed_exts: HashSet<String> = allowed_exts_raw
        .split(',')
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| !s.is_empty())
        .collect();

    info!("FileRecvAPI starting on 0.0.0.0:{port}");
    info!("TIMEZONE: {}", tz);
    info!("SAVING_PATH: {}", base_path.display());
    info!("Allowed extensions: {:?}", allowed_exts);

    let state = AppState {
        base_path,
        allowed_exts,
        api_passwd,
        tz,
    };

    let app = Router::new()
        .route("/", post(upload))
        // No global body size limit; we stream to disk.
        .layer(DefaultBodyLimit::disable())
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;

    Ok(())
}

async fn upload(
    State(state): State<AppState>,
    Query(query): Query<std::collections::HashMap<String, String>>,
    mut multipart: Multipart,
) -> Result<Response, Response> {
    // 1) auth via query ?api_passwd=...
    let Some(given) = query.get("api_passwd") else {
        return Err(Unauthorized.into_response());
    };
    if given != &state.api_passwd {
        return Err(Unauthorized.into_response());
    }

    // 2) find the "file" field
    let mut saved_path: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| BadRequest("invalid multipart form").into_response())?
    {
        // Only handle the 'file' field; ignore others if present
        if field.name() != Some("file") {
            continue;
        }

        // Determine original filename (fallback to 'upload.bin')
        let orig_name = field
            .file_name()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "upload.bin".to_string());

        // Sanitize: strip any path components
        let file_name = Path::new(&orig_name)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("upload.bin")
            .to_string();

        // Compute subdir by extension -> "<ext>_D" or "others_D"
        let ext = Path::new(&file_name)
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.to_ascii_lowercase());

        let subdir = match ext {
            Some(ref e) if state.allowed_exts.contains(e) => format!("{}_D", e),
            _ => "others_D".to_string(),
        };

        // Date in configured timezone
        let now = Utc::now().with_timezone(&state.tz);
        let (y, m, d) = (now.year(), now.month(), now.day());

        // Final directory path: base/subdir/YYYY/MM/DD
        let dir = state
            .base_path
            .join(&subdir)
            .join(format!("{y:04}"))
            .join(format!("{m:02}"))
            .join(format!("{d:02}"));

        fs::create_dir_all(&dir)
            .await
            .map_err(|e| server_err(format!("failed to create dir: {e}")))?;

        let dest_path = dir.join(&file_name);

        // Stream to disk
        let mut f = File::create(&dest_path)
            .await
            .map_err(|e| server_err(format!("failed to create file: {e}")))?;

        let mut field_stream = field;
        while let Some(chunk) = field_stream
            .chunk()
            .await
            .map_err(|e| server_err(format!("read error: {e}")))?
        {
            f.write_all(&chunk)
                .await
                .map_err(|e| server_err(format!("write error: {e}")))?;
        }
        f.flush()
            .await
            .map_err(|e| server_err(format!("flush error: {e}")))?;

        let dest_str = dest_path.to_string_lossy().to_string();
        saved_path = Some(dest_str);
        break; // handle only the first 'file'
    }

    let Some(path) = saved_path else {
        return Err(BadRequest("missing multipart field 'file'").into_response());
    };

    // Return the exact absolute path as plain text (like your examples)
    Ok((StatusCode::OK, path).into_response())
}

fn server_err(msg: String) -> Response {
    error!("{}", msg);
    (StatusCode::INTERNAL_SERVER_ERROR, msg).into_response()
}
