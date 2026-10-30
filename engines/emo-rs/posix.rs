//! Ourin POSIX SHIORI ABI. The Rust/Lua engine remains the upstream Shiori.
#![cfg(unix)]
use crate::shiori::Shiori;
use shiori3::Shiori3;
use lazy_static::lazy_static;
use std::{ffi::{c_void,c_long,c_int}, sync::Mutex, panic::{catch_unwind,AssertUnwindSafe}};
extern "C" { fn malloc(size: usize) -> *mut c_void; fn free(p: *mut c_void); }
lazy_static! { static ref ENGINE: Mutex<Option<Shiori>> = Mutex::new(None); }
const LIMIT: usize = 1_048_576;
unsafe fn input(p: *mut c_void, len: c_long) -> Option<Vec<u8>> {
    if p.is_null() { return None; }
    let result = if len < 0 || len as usize > LIMIT { None }
        else { Some(std::slice::from_raw_parts(p as *const u8, len as usize).to_vec()) };
    free(p); result
}
#[no_mangle]
pub unsafe extern "C" fn load(p: *mut c_void, len: c_long) -> c_int {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(bytes) = input(p,len) else { return 0; };
        let Ok(path) = std::str::from_utf8(&bytes) else { return 0; };
        let Ok(mut slot) = ENGINE.lock() else { return 0; };
        *slot = None;
        match Shiori::load(0, std::path::Path::new(path), &bytes) {
            Ok(engine) => { *slot = Some(engine); 1 },
            Err(error) => { eprintln!("[emo-posix] load: {error:#}"); 0 }
        }
    })).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn request(p: *mut c_void, len: *mut c_long) -> *mut c_void {
    if len.is_null() { if !p.is_null() { free(p); } return std::ptr::null_mut(); }
    let size = *len; *len = 0;
    catch_unwind(AssertUnwindSafe(|| {
        let Some(bytes) = input(p,size) else { return std::ptr::null_mut(); };
        let Ok(text) = std::str::from_utf8(&bytes) else { return std::ptr::null_mut(); };
        let Ok(mut slot) = ENGINE.lock() else { return std::ptr::null_mut(); };
        let Some(engine) = slot.as_mut() else { return std::ptr::null_mut(); };
        let response = match engine.request(text) {
            Ok(response) => response.into_owned(),
            Err(error) => { eprintln!("[emo-posix] request: {error:#}"); return std::ptr::null_mut(); }
        };
        if response.len() > LIMIT { return std::ptr::null_mut(); }
        let out = malloc(response.len()+1);
        if !out.is_null() {
            std::ptr::copy_nonoverlapping(response.as_ptr(),out as *mut u8,response.len());
            *(out as *mut u8).add(response.len())=0; *len=response.len() as c_long;
        }
        out
    })).unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub extern "C" fn unload() -> c_int {
    catch_unwind(AssertUnwindSafe(|| {
        match ENGINE.lock() { Ok(mut slot) => { *slot=None; 1 }, Err(_) => 0 }
    })).unwrap_or(0)
}
