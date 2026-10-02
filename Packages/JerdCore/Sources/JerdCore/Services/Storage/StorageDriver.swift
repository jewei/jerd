import Foundation

public enum StorageDriver {
    public static func server(configuration: StorageConfiguration, runtime: StorageRuntime, paths: StoragePaths) -> ProcessRequest {
        ProcessRequest(executable: runtime.executable, arguments: [
            "server", "--address", "127.0.0.1:\(configuration.apiPort)",
            "--console-enable", "--console-address", "127.0.0.1:\(configuration.consolePort)",
            "--access-key-file", paths.accessKey.path, "--secret-key-file", paths.secretKey.path,
            // RustFS splits volume arguments on spaces. Resolve the fixed local
            // folder from the owned working directory (Application Support has a space).
            "--region", configuration.region, "data"
        ], directory: paths.root, environment: [
            "RUSTFS_OBS_TRACES_EXPORT_ENABLED": "false", "RUSTFS_OBS_METRICS_EXPORT_ENABLED": "false",
            "RUSTFS_OBS_LOGS_EXPORT_ENABLED": "false", "RUSTFS_OBS_LOGGER_LEVEL": "warn",
            "RUSTFS_OBS_PROFILING_EXPORT_ENABLED": "false",
            "RUSTFS_CHECK_UPDATE": "false",
            "RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS": "http://127.0.0.1:\(configuration.consolePort)",
            "RUSTFS_CORS_ALLOWED_ORIGINS": "http://127.0.0.1:\(configuration.consolePort)"
        ])
    }
}
