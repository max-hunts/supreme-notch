enum WiFiSignalLevel: Equatable, Sendable { case strong, medium, weak }
enum GlyphNetworkState: Equatable, Sendable { case wifi(WiFiSignalLevel), ethernet, other, offline }
