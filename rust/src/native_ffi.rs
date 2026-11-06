//! Small C ABI for the SwiftUI iOS/macOS front ends.
//!
//! The Flutter client continues to use flutter_rust_bridge. Native clients call
//! the same Rust core directly and receive UTF-8 JSON envelopes.
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;
use tokio::runtime::Runtime;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn runtime() -> Result<&'static Runtime, String> {
    if let Some(runtime) = RUNTIME.get() {
        return Ok(runtime);
    }
    let created = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|error| error.to_string())?;
    let _ = RUNTIME.set(created);
    RUNTIME
        .get()
        .ok_or_else(|| "Tokio runtime initialization failed".into())
}

unsafe fn text<'a>(value: *const c_char) -> Result<&'a str, String> {
    if value.is_null() {
        return Err("null string argument".into());
    }
    CStr::from_ptr(value)
        .to_str()
        .map_err(|error| error.to_string())
}

fn json_string(value: Result<String, String>) -> *mut c_char {
    let json = match value {
        Ok(value) => serde_json::json!({"ok": true, "value": value}),
        Err(error) => serde_json::json!({"ok": false, "error": error}),
    };
    CString::new(json.to_string())
        .unwrap_or_default()
        .into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn fq_native_set_device_pool_key(
    key: *const u8,
    key_len: usize,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        if key.is_null() || key_len != 32 {
            return Err("device-pool key must contain 32 bytes".into());
        }
        crate::api::set_device_pool_key(std::slice::from_raw_parts(key, key_len).to_vec())?;
        Ok("key provisioned".into())
    }))
    .unwrap_or_else(|_| Err("native core panicked while provisioning the device-pool key".into()));
    json_string(result)
}

#[no_mangle]
pub unsafe extern "C" fn fq_native_init(
    config: *const c_char,
    pool: *const c_char,
    filters: *const c_char,
    runtime_dir: *const c_char,
    port: u16,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let config = text(config)?.to_owned();
        let pool = text(pool)?.to_owned();
        let filters = text(filters)?.to_owned();
        let runtime_dir = text(runtime_dir)?.to_owned();
        runtime()?.block_on(crate::api::init(
            config,
            pool,
            filters,
            runtime_dir,
            port,
            false,
            String::new(),
        ))
    }))
    .unwrap_or_else(|_| Err("native core panicked during initialization".into()));
    json_string(result)
}

/// Returns a loopback resource URL scoped to this launch's capability.
/// Native AVPlayer and image loaders use it for `/src/*` files served by the
/// same Rust core (including range-decrypted CENC video files).
#[no_mangle]
pub unsafe extern "C" fn fq_native_resource_base_url() -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        runtime()?.block_on(async {
            let base = crate::api::base_url().await;
            let capability = crate::api::session_capability().await;
            if base.is_empty() || capability.is_empty() {
                Err("native resource server is not running".to_string())
            } else {
                Ok(format!("{base}/_session/{capability}"))
            }
        })
    }))
    .unwrap_or_else(|_| Err("native core panicked while resolving the media server".into()));
    json_string(result)
}

#[no_mangle]
pub unsafe extern "C" fn fq_native_request(
    method: *const c_char,
    path: *const c_char,
    query: *const c_char,
    body: *const u8,
    body_len: usize,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let method = text(method)?.to_owned();
        let path = text(path)?.to_owned();
        let query = text(query)?.to_owned();
        if body.is_null() && body_len != 0 { return Err("null request body".into()); }
        let body = if body_len == 0 { Vec::new() } else { std::slice::from_raw_parts(body, body_len).to_vec() };
        let response = runtime()?.block_on(crate::api::request(String::new(), method, path, query, body, 30_000))?;
        Ok(serde_json::json!({
            "status": response.status,
            "contentType": response.content_type,
            "bodyBase64": base64::Engine::encode(&base64::engine::general_purpose::STANDARD, response.body),
        }).to_string())
    })).unwrap_or_else(|_| Err("native core panicked during request".into()));
    json_string(result)
}

#[no_mangle]
pub unsafe extern "C" fn fq_native_shutdown() -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        runtime()?.block_on(crate::api::shutdown())?;
        Ok("stopped".into())
    }))
    .unwrap_or_else(|_| Err("native core panicked during shutdown".into()));
    json_string(result)
}

#[no_mangle]
pub unsafe extern "C" fn fq_native_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
