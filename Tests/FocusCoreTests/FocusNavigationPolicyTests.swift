import FocusCore
import Foundation
import Testing

struct FocusNavigationPolicyTests {
    @Test
    func canonicalizesDynamicDetailToDesktopOpusPage() {
        let url = URL(string: "https://t.bilibili.com/123456789")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/opus/123456789"
        )
    }

    @Test
    func canonicalizesMobileOpusPageToDesktopHost() {
        let url = URL(string: "https://m.bilibili.com/opus/987654321")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/opus/987654321"
        )
    }

    @Test
    func canonicalizesVideoPageToFinalDesktopShape() {
        let url = URL(string: "http://m.bilibili.com/video/BV1xx411c7mD?vd_source=abc&p=2&t=30")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/video/BV1xx411c7mD/?p=2&t=30"
        )
    }

    @Test
    func canonicalizesBlackboardVideoPageToFinalDesktopShape() {
        let url = URL(string: "https://www.bilibili.com/blackboard/html5player.html?bvid=BV1xx411c7mD&cid=3000000088&start_progress=123&foo=bar")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/video/BV1xx411c7mD/?cid=3000000088&start_progress=123"
        )
    }
}
