import Foundation
import ReticulumSwift

// MARK: - Constants
let VERSION = Reticulum.version
let APP_NAME = "rnsd"

// MARK: - Daemon Setup
struct rnsd {
    static func main() {
        let userDir = FileManager.default.homeDirectoryForCurrentUser
        var configDir = userDir.appendingPathComponent(".reticulum")
        
        // Simple argument parsing
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "--config-dir" || arg == "-d" {
                if i + 1 < args.count {
                    configDir = URL(fileURLWithPath: args[i + 1])
                    i += 1
                }
            }
            i += 1
        }

        let defaultStorage = configDir.appendingPathComponent("storage")
        let defaultConfig = configDir.appendingPathComponent("config")
        
        var configPath = defaultConfig
        var logLevel: Reticulum.LogLevel = .notice
        
        i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "--config" || arg == "-c" {
                if i + 1 < args.count {
                    configPath = URL(fileURLWithPath: args[i + 1])
                    i += 1
                }
            } else if arg == "-v" {
                logLevel = .info
            } else if arg == "-vv" || arg == "-vvv" {
                logLevel = .debug
            } else if arg == "--version" {
                print("\(APP_NAME) \(VERSION)")
                exit(0)
            } else if arg == "--help" || arg == "-h" {
                print("""
                Usage: \(APP_NAME) [options]
                
                Options:
                  --config-dir, -d <dir>  Path to Reticulum config directory
                  --config, -c <file>     Path to alternative Reticulum config file
                  -v                      Enable info logging
                  -vv, -vvv               Enable debug logging
                  --version               Show version
                  --help, -h              Show this help
                """)
                exit(0)
            }
            i += 1
        }
        
        // Ensure config directory exists
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
        // Ensure storage directory exists
        if !FileManager.default.fileExists(atPath: defaultStorage.path) {
            try? FileManager.default.createDirectory(at: defaultStorage, withIntermediateDirectories: true)
        }
        
        // Load config
        let rnsConfig: ReticulumConfig
        if FileManager.default.fileExists(atPath: configPath.path) {
            if let loaded = ReticulumConfig.load(from: configPath) {
                rnsConfig = loaded
            } else {
                print("Error: Could not parse config at \(configPath.path)")
                exit(1)
            }
        } else {
            print("Notice: No config found at \(configPath.path), using defaults.")
            rnsConfig = ReticulumConfig.parse(ReticulumConfig.defaultConfigText)
            try? ReticulumConfig.defaultConfigText.write(to: configPath, atomically: true, encoding: .utf8)
        }
        
        // Setup Reticulum Configuration
        let config = Reticulum.Configuration(
            storagePath: defaultStorage,
            configPath: configPath,
            shareInstance: rnsConfig.reticulum.shareInstance,
            logLevel: logLevel
        )
        
        // Apply log level before anything else logs.
        Reticulum.globalLogLevel = logLevel

        // Initialize Reticulum
        let reticulum = Reticulum(configuration: config)
        
        do {
            try reticulum.start()
            print("[\(Date())] [Notice] Started \(APP_NAME) version \(VERSION)")
            fflush(stdout)

            // Bind the shared-instance port FIRST so Python clients always see us
            // as the server before they get a chance to bind it themselves.
            // Python's __start_local_interface() first tries to *become* the server;
            // if that fails it falls back to connecting as a client. Binding 37428
            // before synthesizeInterfaces() eliminates the race where Python grabs
            // 37428 then conflicts with our TCPServerInterface on 42422.
            if rnsConfig.reticulum.shareInstance {
                // Use a raw POSIX socket (no SO_REUSEADDR) so Python's LocalServerInterface
                // cannot rebind this port and accidentally become the shared-instance server.
                let localServer = PosixTCPServer(name: "Shared Instance", port: 37428)
                reticulum.transport.register(interface: localServer)
                try localServer.start()
                print("[\(Date())] [Notice] Shared instance server started on port 37428")
                fflush(stdout)

                try reticulum.startRPC(port: 37429)
                print("[\(Date())] [Notice] RPC server started on port 37429")
                fflush(stdout)
            }

            // Now bring up all config-file interfaces (e.g. Docker Bridge on 42422,
            // outbound TCP client interfaces, AutoInterface, etc.)
            print("[\(Date())] [Notice] Synthesizing interfaces from config...")
            fflush(stdout)
            try reticulum.synthesizeInterfaces(from: rnsConfig)

            // Keep the daemon alive
            dispatchMain()
            
        } catch {
            print("Fatal Error: \(error)")
            exit(1)
        }
    }
}

rnsd.main()
