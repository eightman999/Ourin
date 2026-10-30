// The upstream encoding module documents UTF-8 for non-Windows hosts.
use std::io::{Result, Error, ErrorKind};
pub trait Encoder { fn to_string(&self, data: &[u8]) -> Result<String>; fn to_bytes(&self, data: &str) -> Result<Vec<u8>>; }
pub enum Encoding { ANSI, OEM }
impl Encoder for Encoding {
    fn to_string(&self, data: &[u8]) -> Result<String> { String::from_utf8(data.to_vec()).map_err(|e| Error::new(ErrorKind::InvalidData,e)) }
    fn to_bytes(&self, data: &str) -> Result<Vec<u8>> { Ok(data.as_bytes().to_vec()) }
}
