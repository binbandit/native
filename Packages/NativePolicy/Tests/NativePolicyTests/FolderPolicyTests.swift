import Testing

@testable import NativePolicy

@Suite struct FolderPolicyTests {
    @Test func rootsUseComponentBoundaries() {
        let policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.folders.allowedRoots": ["/work"]]))
        #expect(policy.allowsFolder("/work/atlas", canonicalRoots: policy.foldersAllowedRoots))
        #expect(policy.allowsFolder("/work", canonicalRoots: policy.foldersAllowedRoots))
        #expect(!policy.allowsFolder("/work-private/atlas", canonicalRoots: policy.foldersAllowedRoots))
    }

    @Test func malformedOrEmptyRootsDenyAdditions() {
        for roots in [[String](), ["relative"], ["/work", "relative"], "all"] as [Any] {
            let policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.folders.allowedRoots": roots]))
            #expect(!policy.decision(for: .folderAdd).isPermitted)
            #expect(!policy.allowsFolder("/work/atlas", canonicalRoots: policy.foldersAllowedRoots))
        }
        #expect(NativePolicy.default.allowsFolder("/work", canonicalRoots: nil))
    }
}
