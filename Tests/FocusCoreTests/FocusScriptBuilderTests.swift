import FocusCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif
import Testing

struct FocusScriptBuilderTests {
    @Test
    func documentStartScriptIncludesConfigAndPhase() throws {
        let script = try FocusScriptBuilder.makeUserScript(
            for: .documentStart,
            settings: FocusSettings(debugMode: true)
        )

        #expect(script.contains("\"debugMode\":true"))
        #expect(script.contains("documentStart"))
        #expect(script.contains("width=device-width"))
    }

    @Test
    func dynamicRuleMatchesExpectedPage() {
        let dynamicRule = FocusRuleCatalog.defaultRules.first { $0.id == "dynamic-prune" }

        #expect(dynamicRule?.match(host: "t.bilibili.com", path: "/") == true)
        #expect(dynamicRule?.match(host: "www.bilibili.com", path: "/") == false)
    }

    @Test
    func iosVideoBootstrapRunsAtDocumentStartAndStaysPlatformScoped() throws {
        let rule = try #require(FocusRuleCatalog.defaultRules.first { $0.id == "ios-video-bootstrap" })
        let feature = try #require(rule.features.first { $0.featureId == "player-first-frame-layout" })

        #expect(rule.runPhase == .documentStart)
        #expect(rule.match(host: "www.bilibili.com", path: "/video/BV1TEST/"))
        #expect(!rule.match(host: "t.bilibili.com", path: "/video/BV1TEST/"))
        #expect(feature.css.contains("html[data-focus-platform='ios']"))
        #expect(feature.css.contains("focus-native-video-fallback"))
        #expect(feature.css.contains("@media (orientation: landscape)"))
    }

    #if canImport(JavaScriptCore)
    @Test
    func featureScriptsCompileAsJavaScript() throws {
        let context = try #require(JSContext())

        for rule in FocusRuleCatalog.defaultRules {
            for feature in rule.features {
                guard let script = feature.script else {
                    continue
                }

                context.exception = nil
                let wrappedScript = "(function(config, helpers) {\n\(script)\n})"
                let compiledFunction = context.evaluateScript(wrappedScript)

                if compiledFunction == nil || context.exception != nil {
                    let exceptionMessage = context.exception?.toString() ?? "unknown JavaScript error"
                    Issue.record("Failed to compile \(rule.id)/\(feature.featureId): \(exceptionMessage)")
                }

                #expect(compiledFunction != nil)
                #expect(context.exception == nil)
            }
        }
    }
    #endif
}
