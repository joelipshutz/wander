import XCTest

final class BuildConfigurationTests: XCTestCase {
    func testTrackedAuthConfigProvidesReleaseClientKeys() throws {
        let authConfig = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Config/Auth.xcconfig"))
        let settings = Self.xcconfigSettings(in: authConfig)

        let clerkKey = try XCTUnwrap(settings["WANDER_CLERK_PUBLISHABLE_KEY"])
        XCTAssertTrue(clerkKey.hasPrefix("pk_"))
        XCTAssertFalse(clerkKey.contains("$("))

        let supabaseKey = try XCTUnwrap(settings["WANDER_SUPABASE_PUBLISHABLE_KEY"])
        XCTAssertFalse(supabaseKey.isEmpty)
        XCTAssertFalse(supabaseKey.contains("$("))

        XCTAssertTrue(authConfig.contains(#"#include? "LocalAuth.xcconfig""#))
    }

    func testGeneratedProjectDoesNotOverrideAuthConfigWithEmptyKeys() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj"))

        XCTAssertFalse(project.contains(#"WANDER_CLERK_PUBLISHABLE_KEY: """#))
        XCTAssertFalse(project.contains(#"WANDER_SUPABASE_PUBLISHABLE_KEY: """#))
        XCTAssertFalse(generatedProject.contains(#"WANDER_CLERK_PUBLISHABLE_KEY = "";"#))
        XCTAssertFalse(generatedProject.contains(#"WANDER_SUPABASE_PUBLISHABLE_KEY = "";"#))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func xcconfigSettings(in contents: String) -> [String: String] {
        contents
            .split(separator: "\n")
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
    }
}
