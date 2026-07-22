import XCTest
import UIKit
@testable import Wander

final class BuildConfigurationTests: XCTestCase {
    func testTrackedAuthConfigProvidesReleaseClientKeys() throws {
        let authConfig = try String(contentsOf: projectRoot.appendingPathComponent("Wander/Config/Auth.xcconfig"))
        let settings = Self.xcconfigSettings(in: authConfig)

        let clerkKey = try XCTUnwrap(settings["WANDER_CLERK_PUBLISHABLE_KEY"])
        XCTAssertEqual(clerkKey, WanderBackendConfiguration.defaultClerkPublishableKey)
        XCTAssertTrue(clerkKey.hasPrefix("pk_"))
        XCTAssertFalse(clerkKey.contains("$("))

        let supabaseKey = try XCTUnwrap(settings["WANDER_SUPABASE_PUBLISHABLE_KEY"])
        XCTAssertEqual(supabaseKey, WanderBackendConfiguration.defaultSupabasePublishableKey)
        XCTAssertFalse(supabaseKey.isEmpty)
        XCTAssertFalse(supabaseKey.contains("$("))

        XCTAssertEqual(settings["WANDER_POSTHOG_PROJECT_TOKEN"], "")
        XCTAssertTrue(authConfig.contains(#"#include? "LocalAuth.xcconfig""#))
    }

    func testGeneratedProjectDoesNotOverrideAuthConfigWithEmptyKeys() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj"))

        XCTAssertFalse(project.contains(#"WANDER_CLERK_PUBLISHABLE_KEY: """#))
        XCTAssertFalse(project.contains(#"WANDER_SUPABASE_PUBLISHABLE_KEY: """#))
        XCTAssertFalse(project.contains(#"WANDER_POSTHOG_PROJECT_TOKEN: """#))
        XCTAssertFalse(generatedProject.contains(#"WANDER_CLERK_PUBLISHABLE_KEY = "";"#))
        XCTAssertFalse(generatedProject.contains(#"WANDER_SUPABASE_PUBLISHABLE_KEY = "";"#))
        XCTAssertFalse(generatedProject.contains(#"WANDER_POSTHOG_PROJECT_TOKEN = "";"#))
    }

    func testGeneratedProjectUsesAuthConfigForAppBuilds() throws {
        let generatedProject = try String(contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj"))
        let authConfigBuildSettings = generatedProject
            .split(separator: "\n")
            .filter { line in
                line.contains("baseConfigurationReference =") && line.contains("/* Auth.xcconfig */")
            }

        XCTAssertEqual(authConfigBuildSettings.count, 2)
    }

    func testInfoPlistDeclaresAuthConfigurationPlaceholders() throws {
        let plistData = try Data(contentsOf: projectRoot.appendingPathComponent("Wander/Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["WANDER_CLERK_FRONTEND_API"] as? String, "$(WANDER_CLERK_FRONTEND_API)")
        XCTAssertEqual(plist["WANDER_CLERK_PUBLISHABLE_KEY"] as? String, "$(WANDER_CLERK_PUBLISHABLE_KEY)")
        XCTAssertEqual(plist["WANDER_POSTHOG_HOST"] as? String, "$(WANDER_POSTHOG_HOST)")
        XCTAssertEqual(plist["WANDER_POSTHOG_PROJECT_TOKEN"] as? String, "$(WANDER_POSTHOG_PROJECT_TOKEN)")
        XCTAssertEqual(plist["WANDER_SUPABASE_PUBLISHABLE_KEY"] as? String, "$(WANDER_SUPABASE_PUBLISHABLE_KEY)")
        XCTAssertEqual(plist["WANDER_SUPABASE_URL"] as? String, "$(WANDER_SUPABASE_URL)")
    }

    func testInfoPlistRegistersProfileShareURLScheme() throws {
        let plistData = try Data(contentsOf: projectRoot.appendingPathComponent("Wander/Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        XCTAssertTrue(schemes.contains("recme"))
    }

    func testUserFacingBrandUsesRecmeWithoutChangingStableIdentifiers() throws {
        let plistData = try Data(contentsOf: projectRoot.appendingPathComponent("Wander/Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj"))

        XCTAssertEqual(AppBrand.displayName, "rec.me")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "rec.me")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")

        for key in ["NSCameraUsageDescription", "NSLocationWhenInUseUsageDescription"] {
            let usageDescription = try XCTUnwrap(plist[key] as? String)
            XCTAssertTrue(usageDescription.contains("rec.me"), "\(key) must use the public app name")
            XCTAssertFalse(usageDescription.contains("Wander"), "\(key) must not expose the internal app name")
        }

        XCTAssertTrue(project.contains("CFBundleDisplayName: rec.me"))
        XCTAssertTrue(project.contains("PRODUCT_NAME: Wander"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.grayline.wander"))
        XCTAssertTrue(generatedProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.grayline.wander;"))
    }

    func testAppIconRenditionsHaveRequiredSizesAndNoAlpha() throws {
        let iconDirectory = projectRoot.appendingPathComponent(
            "Wander/Resources/Assets.xcassets/AppIcon.appiconset",
            isDirectory: true
        )
        let expectedSizes = [
            "Icon-20@2x.png": 40,
            "Icon-20@3x.png": 60,
            "Icon-29@2x.png": 58,
            "Icon-29@3x.png": 87,
            "Icon-40@2x.png": 80,
            "Icon-40@3x.png": 120,
            "Icon-60@2x.png": 120,
            "Icon-60@3x.png": 180,
            "Icon-1024.png": 1024
        ]

        for (filename, expectedPixels) in expectedSizes {
            let data = try Data(contentsOf: iconDirectory.appendingPathComponent(filename))
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage, filename)
            XCTAssertEqual(image.width, expectedPixels, filename)
            XCTAssertEqual(image.height, expectedPixels, filename)

            switch image.alphaInfo {
            case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
                XCTFail("\(filename) must not contain an alpha channel")
            case .none, .noneSkipFirst, .noneSkipLast:
                break
            @unknown default:
                XCTFail("\(filename) has an unknown alpha configuration")
            }
        }
    }

    func testAppIconContractIsDiscoverableByFutureAgents() throws {
        let agents = try String(contentsOf: projectRoot.appendingPathComponent("AGENTS.md"))
        let contract = try String(contentsOf: projectRoot.appendingPathComponent("docs/brand/recme-app-icon.md"))
        let releaseHelper = try String(contentsOf: projectRoot.appendingPathComponent("scripts/testflight-release.mjs"))
        let generator = projectRoot.appendingPathComponent("scripts/generate-app-icon-renditions.sh")

        XCTAssertTrue(agents.contains("docs/brand/recme-app-icon.md"))
        XCTAssertTrue(agents.contains("scripts/generate-app-icon-renditions.sh"))
        XCTAssertTrue(contract.contains("folded map/page corner"))
        XCTAssertTrue(contract.contains("pencil"))
        XCTAssertTrue(releaseHelper.contains(#"groupName: "rec.me Alpha""#))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: generator.path))
    }

    func testTrackedClerkPublishableKeyDecodesToDefaultFrontendAPI() throws {
        let clerkKey = WanderBackendConfiguration.defaultClerkPublishableKey
        let encoded = try XCTUnwrap(clerkKey.split(separator: "_").last).description
        let decodedData = try XCTUnwrap(Data(base64Encoded: encoded))
        let decoded = try XCTUnwrap(String(data: decodedData, encoding: .utf8))

        XCTAssertEqual(decoded, "\(WanderBackendConfiguration.defaultClerkFrontendAPI)$")
    }

    func testRuntimeConfigurationFallsBackWhenInfoPlistValuesAreUnresolved() {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }

        XCTAssertEqual(configuration.clerkPublishableKey, WanderBackendConfiguration.defaultClerkPublishableKey)
        XCTAssertEqual(configuration.clerkFrontendAPI, WanderBackendConfiguration.defaultClerkFrontendAPI)
        XCTAssertEqual(configuration.supabaseURL?.absoluteString, WanderBackendConfiguration.defaultSupabaseURLString)
        XCTAssertEqual(configuration.supabasePublishableKey, WanderBackendConfiguration.defaultSupabasePublishableKey)
        XCTAssertTrue(configuration.isClerkConfigured)
        XCTAssertTrue(configuration.isSupabaseConfigured)
    }

    func testRuntimeConfigurationKeepsExplicitOverrides() {
        let configuration = WanderBackendConfiguration.current { key in
            switch key {
            case "WANDER_CLERK_PUBLISHABLE_KEY":
                "pk_test_bW9jay5jbGVyay5hY2NvdW50cy5kZXYk"
            case "WANDER_CLERK_FRONTEND_API":
                "mock.clerk.accounts.dev"
            case "WANDER_SUPABASE_URL":
                "https://example.supabase.co"
            case "WANDER_SUPABASE_PUBLISHABLE_KEY":
                "override-supabase-key"
            default:
                nil
            }
        }

        XCTAssertEqual(configuration.clerkPublishableKey, "pk_test_bW9jay5jbGVyay5hY2NvdW50cy5kZXYk")
        XCTAssertEqual(configuration.clerkFrontendAPI, "mock.clerk.accounts.dev")
        XCTAssertEqual(configuration.supabaseURL?.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(configuration.supabasePublishableKey, "override-supabase-key")
    }

    func testPostHogRuntimeConfigurationFallsBackWhenInfoPlistValuesAreUnresolved() {
        let configuration = PostHogAnalyticsConfiguration.current { key in
            "$(\(key))"
        }

        XCTAssertNil(configuration.projectToken)
        XCTAssertEqual(configuration.host, PostHogAnalyticsConfiguration.defaultHost)
        XCTAssertFalse(configuration.isConfigured)
    }

    func testPostHogRuntimeConfigurationKeepsExplicitOverrides() {
        let configuration = PostHogAnalyticsConfiguration.current { key in
            switch key {
            case "WANDER_POSTHOG_PROJECT_TOKEN":
                "phc_recme_project"
            case "WANDER_POSTHOG_HOST":
                "https://eu.i.posthog.com"
            default:
                nil
            }
        }

        XCTAssertEqual(configuration.projectToken, "phc_recme_project")
        XCTAssertEqual(configuration.host, "https://eu.i.posthog.com")
        XCTAssertTrue(configuration.isConfigured)
    }

    func testUnauthorizedRPCStatusRequiresOneFreshTokenRetry() {
        XCTAssertTrue(WanderSupabaseClient.requiresFreshToken(after: 401))
        XCTAssertTrue(WanderSupabaseClient.requiresFreshToken(after: 403))
        XCTAssertFalse(WanderSupabaseClient.requiresFreshToken(after: 400))
        XCTAssertFalse(WanderSupabaseClient.requiresFreshToken(after: 500))
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
                let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
    }
}
