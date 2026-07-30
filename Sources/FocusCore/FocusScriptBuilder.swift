import Foundation

public enum FocusScriptBuilder {
    public static func makeUserScript(
        for phase: FocusPageRule.RunPhase,
        settings: FocusSettings,
        rules: [FocusPageRule] = FocusRuleCatalog.defaultRules
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let configJSON = try encode(settings.effectiveRuntimeSettings, with: encoder)
        let rulesJSON = try encode(rules, with: encoder)

        return FocusScriptSource.runtimeTemplate
            .replacingOccurrences(of: "__FOCUS_CONFIG_JSON__", with: configJSON)
            .replacingOccurrences(of: "__FOCUS_RULES_JSON__", with: rulesJSON)
            .replacingOccurrences(of: "__FOCUS_PHASE__", with: phase.rawValue)
    }

    private static func encode<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
