import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct PHPFileRenderingTests {
    @Test func thePoolFileHasTheExactTextAndOneBudget() throws {
        let text = try FPMPoolRenderer.render(socket: URL(fileURLWithPath: "/tmp/jerd-abc/php-0.sock"))
        #expect(
            text == """
                [global]
                daemonize = no
                error_log = /dev/stderr
                log_level = notice
                process_control_timeout = 2s
                [jerd]
                listen = "/tmp/jerd-abc/php-0.sock"
                listen.mode = 0600
                ping.path = /.jerd/fpm-ping
                ping.response = Jerd FPM is ready.
                pm = ondemand
                pm.max_children = 8
                pm.process_idle_timeout = 5s
                pm.max_requests = 100
                clear_env = yes
                catch_workers_output = yes
                security.limit_extensions = .php
                request_terminate_timeout = 30s
                chdir = /

                """)
        #expect(!text.contains("user ="))
    }

    @Test func theProxyWaitsLongerThanPHPAndFPM() {
        #expect(RequestTimeBudget.proxyReadSeconds > RequestTimeBudget.fpmTerminateSeconds)
        #expect(RequestTimeBudget.proxyReadSeconds > RequestTimeBudget.phpExecutionSeconds)
        #expect(PHPIniPolicy.fpm.contains("max_execution_time = \(RequestTimeBudget.phpExecutionSeconds)\n"))
    }

    @Test func aSocketPathOf104BytesIsTooLong() throws {
        let path = "/" + String(repeating: "s", count: 103)
        #expect(throws: JerdError.invalid("PHP socket path is too long.")) {
            try FPMPoolRenderer.render(socket: URL(fileURLWithPath: path))
        }
        #expect(throws: Never.self) {
            try FPMPoolRenderer.render(socket: URL(fileURLWithPath: String(path.dropLast())))
        }
    }

    @Test func iniQuotingEscapesQuotesAndBackslashesAndRefusesSubstitutions() throws {
        #expect(try INIString.quote("/a \"b\"\\c") == "\"/a \\\"b\\\"\\\\c\"")
        let refused = JerdError.invalid(
            "Configuration paths cannot contain control characters or environment substitutions.")
        for value in ["/x/${HOME}", "/x\ny", "/x\u{0}y", "/x\ty"] {
            #expect(throws: refused) { try INIString.quote(value) }
        }
    }

    @Test func theINITemplatesAreExact() throws {
        #expect(PHPIniPolicy.common == "[PHP]\ndate.timezone = UTC\nexpose_php = Off\nlog_errors = On\n")
        #expect(
            PHPIniPolicy.fpm == PHPIniPolicy.common
                + "memory_limit = 256M\nupload_max_filesize = 32M\npost_max_size = 40M\nmax_execution_time = 30\n"
                + "display_errors = Off\ncgi.fix_pathinfo = 1\n[opcache]\nopcache.enable = 1\n"
                + "opcache.validate_timestamps = 1\nopcache.revalidate_freq = 0\n")
        #expect(
            PHPIniPolicy.cli == PHPIniPolicy.common
                + "memory_limit = -1\nmax_execution_time = 0\ndisplay_errors = stderr\n[opcache]\nopcache.enable_cli = 0\n"
        )
    }

    @Test func theTrustSectionPointsCURLAndOpenSSLAtTheBundle() throws {
        #expect(try PHPIniPolicy.trustSection(caBundle: nil) == "")
        let bundle = URL(fileURLWithPath: "/a b/php-ca.pem")
        let section = "\n[curl]\ncurl.cainfo = \"/a b/php-ca.pem\"\n[openssl]\nopenssl.cafile = \"/a b/php-ca.pem\"\n"
        #expect(try PHPIniPolicy.trustSection(caBundle: bundle) == section)
        #expect(try PHPIniPolicy.fpmFile(caBundle: bundle) == PHPIniPolicy.fpm + section)
        #expect(try PHPIniPolicy.cliFile(caBundle: nil) == PHPIniPolicy.cli)
        #expect(throws: JerdError.self) { try PHPIniPolicy.trustSection(caBundle: URL(fileURLWithPath: "/${X}.pem")) }
    }
}
