import Darwin
import JerdDatabases
import Testing

@Suite struct DatabaseEngineTests {
    @Test func everyEngineNamesItsExecutablesPortsAndAccounts() {
        #expect(DatabaseEngine.mysql.title == "MySQL")
        #expect(DatabaseEngine.postgresql.defaultPort == 5_432)
        #expect(DatabaseEngine.redis.serverName == "redis-server")
        #expect(DatabaseEngine.postgresql.clientName == "psql")
        #expect(DatabaseEngine.redis.username == "default")
        #expect(DatabaseEngine.mysql.username == "jerd")
        #expect(DatabaseEngine.postgresql.database == "postgres")
        #expect(DatabaseEngine.redis.database == "0")
    }

    @Test func onlyPostgresStopsWithItsFastShutdownSignal() {
        #expect(DatabaseEngine.postgresql.stopSignal == SIGINT)
        #expect(DatabaseEngine.mysql.stopSignal == SIGTERM)
        #expect(DatabaseEngine.redis.stopSignal == SIGTERM)
    }
}
