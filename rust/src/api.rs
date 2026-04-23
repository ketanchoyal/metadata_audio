#[flutter_rust_bridge::frb]
pub fn health_check() -> String {
    "symphonia-native-ok".to_string()
}
