import Testing

@testable import JerdUI

@Suite("Storage bucket detail")
struct StorageBucketDetailTests {
    @Test("The Buckets row asks for RustFS only after a load that found no runtime")
    func asksForRustFSOnlyWhenLoaded() {
        let install = "Install RustFS first. Then give your application an S3 bucket for uploads and files."
        #expect(StorageOverviewPage.bucketDetail(loadState: .loaded, hasRuntime: false, bucketCount: 0) == install)
        #expect(StorageOverviewPage.bucketDetail(loadState: .loading, hasRuntime: false, bucketCount: 0) != install)
        #expect(
            StorageOverviewPage.bucketDetail(loadState: .failed(message: "x"), hasRuntime: false, bucketCount: 0)
                != install)
        #expect(StorageOverviewPage.bucketDetail(loadState: .loaded, hasRuntime: true, bucketCount: 0) != install)
    }

    @Test("The Buckets row points to the sidebar when buckets exist")
    func pointsToSidebarWithBuckets() {
        #expect(
            StorageOverviewPage.bucketDetail(loadState: .loaded, hasRuntime: true, bucketCount: 2)
                == "Select a bucket in the sidebar to see its connection and access settings.")
    }
}
