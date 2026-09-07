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

    func testInstagramSharingUsesRegisteredMetaApp() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj")
        )
        let plistData = try Data(
            contentsOf: projectRoot.appendingPathComponent("Wander/Resources/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let querySchemes = try XCTUnwrap(plist["LSApplicationQueriesSchemes"] as? [String])

        XCTAssertTrue(project.contains(#"WANDER_META_APP_ID: "1056841943950470""#))
        XCTAssertTrue(generatedProject.contains("WANDER_META_APP_ID = 1056841943950470;"))
        XCTAssertEqual(plist["WANDER_META_APP_ID"] as? String, "$(WANDER_META_APP_ID)")
        XCTAssertTrue(querySchemes.contains("instagram"))
        XCTAssertTrue(querySchemes.contains("instagram-stories"))
        XCTAssertTrue(
            try XCTUnwrap(plist["NSPhotoLibraryAddUsageDescription"] as? String)
                .contains("Instagram")
        )
    }

    func testSnapchatSharingUsesRegisteredStagingClient() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj")
        )
        let plistData = try Data(
            contentsOf: projectRoot.appendingPathComponent("Wander/Resources/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let querySchemes = try XCTUnwrap(plist["LSApplicationQueriesSchemes"] as? [String])

        XCTAssertTrue(
            project.contains(
                "WANDER_SNAPCHAT_CLIENT_ID: 9ff6b79b-97ce-435c-bf7a-5176638246a0"
            )
        )
        XCTAssertTrue(
            generatedProject.contains(
                #"WANDER_SNAPCHAT_CLIENT_ID = "9ff6b79b-97ce-435c-bf7a-5176638246a0";"#
            )
        )
        XCTAssertEqual(
            plist["WANDER_SNAPCHAT_CLIENT_ID"] as? String,
            "$(WANDER_SNAPCHAT_CLIENT_ID)"
        )
        XCTAssertTrue(querySchemes.contains("snapchat"))
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

    func testAppEntitlementsRegisterGetRecMeUniversalLinks() throws {
        let entitlementsData = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Resources/Wander.entitlements"
            )
        )
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: entitlementsData,
                format: nil
            ) as? [String: Any]
        )
        let associatedDomains = try XCTUnwrap(
            entitlements["com.apple.developer.associated-domains"] as? [String]
        )

        XCTAssertTrue(associatedDomains.contains("applinks:getrec.me"))
        XCTAssertTrue(associatedDomains.contains("webcredentials:clerk.getrec.me"))
        XCTAssertFalse(associatedDomains.contains(where: { $0.contains("clerk.accounts.dev") }))
    }

    func testAppEntitlementsEnableSignInWithApple() throws {
        let entitlementsData = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Resources/Wander.entitlements"
            )
        )
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: entitlementsData,
                format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(
            entitlements["com.apple.developer.applesignin"] as? [String],
            ["Default"]
        )
    }

    func testClerkDependencyIncludesAcceptedAuthCompletionOrdering() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"))
        let resolvedData = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            )
        )
        let resolved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: resolvedData) as? [String: Any]
        )
        let pins = try XCTUnwrap(resolved["pins"] as? [[String: Any]])
        let clerk = try XCTUnwrap(pins.first { $0["identity"] as? String == "clerk-ios" })
        let state = try XCTUnwrap(clerk["state"] as? [String: Any])

        XCTAssertTrue(project.contains("from: 1.5.0"))
        XCTAssertEqual(state["version"] as? String, "1.5.0")
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

    func testOnboardingMastheadUsesAstirLockupAndKeepsMapWordmarkAssetValid() throws {
        let assetDirectory = projectRoot.appendingPathComponent(
            "Wander/Resources/Assets.xcassets/RecmeMapWordmark.imageset",
            isDirectory: true
        )
        let imageData = try Data(
            contentsOf: assetDirectory.appendingPathComponent("RecmeMapWordmark.png")
        )
        let image = try XCTUnwrap(UIImage(data: imageData)?.cgImage)
        let manifest = try String(
            contentsOf: assetDirectory.appendingPathComponent("Contents.json")
        )
        let onboardingSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Onboarding/LoggedOutCarouselView.swift"
            )
        )

        XCTAssertEqual(image.width, 896)
        XCTAssertEqual(image.height, 200)
        XCTAssertTrue(manifest.contains(#""filename" : "RecmeMapWordmark.png""#))
        XCTAssertTrue(onboardingSource.contains("AstirMastheadLockup(isCompact: true)"))
    }

    func testIconComposerAppIconIsProjectBound() throws {
        let iconDirectory = projectRoot.appendingPathComponent(
            "Wander/Resources/AppIcon.icon",
            isDirectory: true
        )
        let sourceURL = iconDirectory.appendingPathComponent(
            "Assets/recme-warm-map-original.png"
        )
        let documentData = try Data(
            contentsOf: iconDirectory.appendingPathComponent("icon.json")
        )
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: documentData) as? [String: Any]
        )
        let groups = try XCTUnwrap(document["groups"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        let layers = try XCTUnwrap(group["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers.first)
        let sourceImage = try XCTUnwrap(
            UIImage(data: Data(contentsOf: sourceURL))?.cgImage
        )
        let project = try String(
            contentsOf: projectRoot.appendingPathComponent("project.yml")
        )
        let generatedProject = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/project.pbxproj")
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group["blur-material"] as? Double, 0)
        XCTAssertEqual(
            layer["image-name"] as? String,
            "recme-warm-map-original.png"
        )
        XCTAssertEqual(sourceImage.width, 1024)
        XCTAssertEqual(sourceImage.height, 1024)
        XCTAssertEqual(
            try Data(contentsOf: sourceURL),
            try Data(contentsOf: projectRoot.appendingPathComponent(
                "Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
            ))
        )
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        XCTAssertTrue(generatedProject.contains("AppIcon.icon in Resources"))
    }

    func testAppIconContractIsDiscoverableByFutureAgents() throws {
        let agents = try String(contentsOf: projectRoot.appendingPathComponent("AGENTS.md"))
        let contract = try String(contentsOf: projectRoot.appendingPathComponent("docs/brand/recme-app-icon.md"))
        let releaseHelper = try String(contentsOf: projectRoot.appendingPathComponent("scripts/testflight-release.mjs"))
        let masterGenerator = projectRoot.appendingPathComponent("scripts/generate-app-icon-master.swift")
        let renditionGenerator = projectRoot.appendingPathComponent("scripts/generate-app-icon-renditions.sh")
        let masterGeneratorSource = try String(contentsOf: masterGenerator)

        XCTAssertTrue(agents.contains("docs/brand/recme-app-icon.md"))
        XCTAssertTrue(agents.contains("scripts/generate-app-icon-master.swift"))
        XCTAssertTrue(agents.contains("scripts/generate-app-icon-renditions.sh"))
        XCTAssertTrue(contract.contains("warm matte neighborhood map"))
        XCTAssertTrue(contract.contains("selected full-frame"))
        XCTAssertTrue(contract.contains("rec.me"))
        XCTAssertTrue(masterGeneratorSource.contains("recme-warm-map-original.png"))
        XCTAssertTrue(masterGeneratorSource.contains("1024 x 1024"))
        XCTAssertTrue(masterGeneratorSource.contains("must be opaque"))
        XCTAssertTrue(releaseHelper.contains(#"groupName: "rec.me Alpha""#))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: masterGenerator.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: renditionGenerator.path))
    }

    func testTrackedClerkPublishableKeyDecodesToDefaultFrontendAPI() throws {
        let clerkKey = WanderBackendConfiguration.defaultClerkPublishableKey
        let encoded = try XCTUnwrap(clerkKey.split(separator: "_").last).description
        let paddingCount = (4 - encoded.count % 4) % 4
        let paddedEncoded = encoded + String(repeating: "=", count: paddingCount)
        let decodedData = try XCTUnwrap(Data(base64Encoded: paddedEncoded))
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

    func testPostHogDisablesUnusedAutomaticCaptureSurfaces() {
        #if canImport(PostHog)
        let configuration = PostHogAnalyticsClient.sdkConfiguration(
            projectToken: "phc_recme_project",
            host: "https://us.i.posthog.com"
        )

        XCTAssertFalse(configuration.captureApplicationLifecycleEvents)
        XCTAssertFalse(configuration.captureScreenViews)
        XCTAssertFalse(configuration.captureElementInteractions)
        XCTAssertFalse(configuration.enableSwizzling)
        XCTAssertFalse(configuration.sessionReplay)
        XCTAssertFalse(configuration.surveys)
        XCTAssertFalse(configuration.errorTrackingConfig.autoCapture)
        XCTAssertFalse(configuration.setDefaultPersonProperties)
        #endif
    }

    func testAnalyticsPrivacySanitizerDropsPrivatePayloadsAndTruncatesValues() {
        let event = WanderAnalyticsSchema.sanitized(
            AnalyticsEvent(
                name: "privacy_probe",
                properties: [
                    "place_name": "Private place",
                    "note": "Private note",
                    "phone_number": "+15551234567",
                    "status": String(repeating: "a", count: 140)
                ]
            )
        )

        XCTAssertNil(event.properties["place_name"])
        XCTAssertNil(event.properties["note"])
        XCTAssertNil(event.properties["phone_number"])
        XCTAssertEqual(event.properties["status"]?.count, 128)
    }

    func testContextualAnalyticsAddsSchemaAndBuildContext() throws {
        let recording = BuildConfigurationRecordingAnalyticsClient()
        let analytics = ContextualAnalyticsClient(client: recording, platform: "ios_test")

        analytics.track(AnalyticsEvent(name: "context_probe", properties: ["surface": "test"]))

        let event = try XCTUnwrap(recording.events.first)
        XCTAssertEqual(event.properties["analytics_schema_version"], WanderAnalyticsSchema.version)
        XCTAssertEqual(event.properties["platform"], "ios_test")
        XCTAssertNotNil(event.properties["app_version"])
        XCTAssertNotNil(event.properties["build_number"])
    }

    @MainActor
    func testLifecycleTracksFirstOpenOnlyOnceAndEveryColdSession() throws {
        let suiteName = "BuildConfigurationTests.analytics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recording = BuildConfigurationRecordingAnalyticsClient()

        let firstTracker = AppAnalyticsLifecycleTracker(analytics: recording, defaults: defaults)
        firstTracker.recordLaunch()
        firstTracker.recordLaunch()
        let secondTracker = AppAnalyticsLifecycleTracker(analytics: recording, defaults: defaults)
        secondTracker.recordLaunch()

        XCTAssertEqual(
            recording.events.filter { $0.name == WanderAnalyticsEvents.appFirstOpened }.count,
            1
        )
        XCTAssertEqual(
            recording.events.filter { $0.name == WanderAnalyticsEvents.appSessionStarted }.count,
            2
        )
    }

    func testAcquisitionAttributionAllowListsAndSanitizesCampaignProperties() throws {
        let url = try XCTUnwrap(
            URL(string: "https://getrec.me/import/google?utm_source=tiktok&utm_campaign=summer%20launch&utm_term=private&utm_content=a%2Fb")
        )
        let attribution = try XCTUnwrap(AcquisitionAttribution(url: url))

        XCTAssertEqual(attribution.properties["route"], "import")
        XCTAssertEqual(attribution.properties["utm_source"], "tiktok")
        XCTAssertEqual(attribution.properties["utm_campaign"], "summer launch")
        XCTAssertEqual(attribution.properties["utm_content"], "ab")
        XCTAssertNil(attribution.properties["utm_term"])
        XCTAssertNil(attribution.properties["url"])
    }

    func testAnalyticsDashboardAndMaintenanceDocsStayCheckedIn() throws {
        let dashboard = try String(
            contentsOf: projectRoot.appendingPathComponent("scripts/posthog-product-dashboard.mjs")
        )
        let analyticsDocs = try String(
            contentsOf: projectRoot.appendingPathComponent("docs/analytics.md")
        )
        let agentInstructions = try String(
            contentsOf: projectRoot.appendingPathComponent("AGENTS.md")
        )

        for section in ["Acquisition", "Activation", "Engagement", "Retention", "Referrals", "Monetization"] {
            XCTAssertTrue(dashboard.contains("title: \"\(section)\""))
        }
        XCTAssertTrue(analyticsDocs.contains("engagement_action_performed"))
        XCTAssertTrue(agentInstructions.contains("## Analytics Maintenance"))
    }

    func testAppPrivacyManifestDeclaresAppOwnedDataAndRequiredReasons() throws {
        let manifest = try privacyManifest("Wander/Resources/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertEqual(
            try collectedDataTypes(in: manifest),
            [
                "NSPrivacyCollectedDataTypeContacts",
                "NSPrivacyCollectedDataTypeDeviceID",
                "NSPrivacyCollectedDataTypeEmailAddress",
                "NSPrivacyCollectedDataTypeName",
                "NSPrivacyCollectedDataTypeOtherUserContent",
                "NSPrivacyCollectedDataTypePhoneNumber",
                "NSPrivacyCollectedDataTypePhotosorVideos",
                "NSPrivacyCollectedDataTypeSearchHistory",
                "NSPrivacyCollectedDataTypeUserID"
            ]
        )
        XCTAssertEqual(
            try accessedAPIReasons(in: manifest),
            [
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
                "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
            ]
        )

        for declaration in try collectedDataDeclarations(in: manifest) {
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        }
    }

    func testShareExtensionPrivacyManifestDeclaresOnlyContainerFileTimestamps() throws {
        let manifest = try privacyManifest("WanderShareExtension/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertEqual(try collectedDataTypes(in: manifest), [])
        XCTAssertEqual(
            try accessedAPIReasons(in: manifest),
            ["NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]]
        )
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

    private func privacyManifest(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func collectedDataDeclarations(in manifest: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    }

    private func collectedDataTypes(in manifest: [String: Any]) throws -> [String] {
        try collectedDataDeclarations(in: manifest)
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
            .sorted()
    }

    private func accessedAPIReasons(in manifest: [String: Any]) throws -> [String: [String]] {
        let declarations = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return try Dictionary(uniqueKeysWithValues: declarations.map { declaration in
            let category = try XCTUnwrap(declaration["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try XCTUnwrap(declaration["NSPrivacyAccessedAPITypeReasons"] as? [String])
            return (category, reasons.sorted())
        })
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

private final class BuildConfigurationRecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}
