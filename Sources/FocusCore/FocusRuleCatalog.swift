import Foundation

public enum FocusRuleCatalog {
    public static let defaultRules: [FocusPageRule] = [
        FocusPageRule(
            id: "global-viewport",
            hosts: ["bilibili.com", "www.bilibili.com", "m.bilibili.com", "t.bilibili.com", "search.bilibili.com"],
            runPhase: .documentStart,
            metaViewport: "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no",
            features: []
        ),
        FocusPageRule(
            id: "ios-video-bootstrap",
            hosts: ["bilibili.com", "m.bilibili.com", "www.bilibili.com"],
            pathPrefixes: ["/video/", "/bangumi/play/", "/blackboard/html5player.html", "/blackboard/html5mobileplayer.html"],
            runPhase: .documentStart,
            features: [
                FocusFeature(
                    featureId: "player-first-frame-layout",
                    requiredSelectors: [],
                    optionalSelectors: ["#playerWrap", ".left-container", ".right-container", ".video-pod"],
                    action: .repair,
                    css: """
                    html[data-focus-platform='ios'],
                    html[data-focus-platform='ios'] body,
                    html[data-focus-platform='ios'] #app,
                    html[data-focus-platform='ios'] main,
                    html[data-focus-platform='ios'] #mirror-vdcon,
                    html[data-focus-platform='ios'] .video-container,
                    html[data-focus-platform='ios'] .video-container-v1 {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                      box-sizing: border-box !important;
                    }

                    html[data-focus-platform='ios'] #mirror-vdcon.video-container-v1,
                    html[data-focus-platform='ios'] .video-container-v1,
                    html[data-focus-platform='ios'] .video-container {
                      display: flex !important;
                      flex-direction: column !important;
                      align-items: stretch !important;
                    }

                    html[data-focus-platform='ios'] .left-container,
                    html[data-focus-platform='ios'] .left-container.scroll-sticky {
                      display: flex !important;
                      flex-direction: column !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                      position: static !important;
                      inset: auto !important;
                    }

                    html[data-focus-platform='ios'] #playerWrap,
                    html[data-focus-platform='ios'] .player-wrap,
                    html[data-focus-platform='ios'] #bilibili-player,
                    html[data-focus-platform='ios'] .bpx-player-container,
                    html[data-focus-platform='ios'] .player-container,
                    html[data-focus-platform='ios'] .bpx-player-video-wrap {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin-left: auto !important;
                      margin-right: auto !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                      position: relative !important;
                      overflow: hidden !important;
                      background: #000 !important;
                    }

                    html[data-focus-platform='ios'] .bpx-player-primary-area,
                    html[data-focus-platform='ios'] .bpx-player-video-area,
                    html[data-focus-platform='ios'] .bpx-player-video-wrap,
                    html[data-focus-platform='ios'] .bpx-player-video-perch,
                    html[data-focus-platform='ios'] .bpx-player-video-screen,
                    html[data-focus-platform='ios'] .bilibili-player-video,
                    html[data-focus-platform='ios'] .bilibili-player-video-wrap {
                      width: 100% !important;
                      max-width: 100% !important;
                      margin-left: auto !important;
                      margin-right: auto !important;
                      display: flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      box-sizing: border-box !important;
                      overflow: hidden !important;
                      background: #000 !important;
                    }

                    html[data-focus-platform='ios'] #playerWrap video,
                    html[data-focus-platform='ios'] #bilibili-player video,
                    html[data-focus-platform='ios'] .bpx-player-container video,
                    html[data-focus-platform='ios'] .player-container video,
                    html[data-focus-platform='ios'] .bpx-player-video-wrap video,
                    html[data-focus-platform='ios'] .bpx-player-video-area video,
                    html[data-focus-platform='ios'] .bilibili-player-video video {
                      display: block !important;
                      width: 100% !important;
                      max-width: 100% !important;
                      height: 100% !important;
                      margin: auto !important;
                      object-fit: contain !important;
                      object-position: center center !important;
                      transform: none !important;
                    }

                    @media (orientation: portrait) {
                      html[data-focus-platform='ios'] #playerWrap,
                      html[data-focus-platform='ios'] .player-wrap,
                      html[data-focus-platform='ios'] #bilibili-player,
                      html[data-focus-platform='ios'] .bpx-player-container,
                      html[data-focus-platform='ios'] .player-container,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap {
                        height: calc(100vw / 1.5) !important;
                        min-height: 0 !important;
                        max-height: none !important;
                        aspect-ratio: 3 / 2 !important;
                      }

                      html[data-focus-platform='ios'] .bpx-player-primary-area,
                      html[data-focus-platform='ios'] .bpx-player-video-area,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap,
                      html[data-focus-platform='ios'] .bpx-player-video-perch,
                      html[data-focus-platform='ios'] .bpx-player-video-screen,
                      html[data-focus-platform='ios'] .bilibili-player-video,
                      html[data-focus-platform='ios'] .bilibili-player-video-wrap {
                        height: 100% !important;
                        min-height: 0 !important;
                        max-height: 100% !important;
                      }
                    }

                    @media (orientation: landscape) {
                      html[data-focus-platform='ios'] #playerWrap,
                      html[data-focus-platform='ios'] .player-wrap,
                      html[data-focus-platform='ios'] #bilibili-player,
                      html[data-focus-platform='ios'] .bpx-player-container,
                      html[data-focus-platform='ios'] .player-container,
                      html[data-focus-platform='ios'] .bpx-player-primary-area,
                      html[data-focus-platform='ios'] .bpx-player-video-area,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap,
                      html[data-focus-platform='ios'] .bpx-player-video-perch,
                      html[data-focus-platform='ios'] .bpx-player-video-screen,
                      html[data-focus-platform='ios'] .bilibili-player-video,
                      html[data-focus-platform='ios'] .bilibili-player-video-wrap {
                        width: 100vw !important;
                        min-width: 100vw !important;
                        max-width: 100vw !important;
                        height: 100vh !important;
                        min-height: 100vh !important;
                        max-height: 100vh !important;
                        margin: 0 !important;
                        aspect-ratio: auto !important;
                      }
                    }

                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .right-container,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .right-container-inner,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .video-pod,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .video-pod__head,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .video-pod__header,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .video-pod__body,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .video-pod__list,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) .multi-page,
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) [class*='multi-page'],
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) [class*='episode-list'],
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) [class*='part-list'],
                    html[data-focus-platform='ios']:not(.focus-native-video-fallback) [class*='page-list'] {
                      visibility: hidden !important;
                      opacity: 0 !important;
                      pointer-events: none !important;
                    }
                    """,
                    script: """
                    const state = helpers.featureState;
                    const pageKey = String(location.pathname || '') + String(location.search || '');
                    if (state.pageKey !== pageKey) {
                      state.pageKey = pageKey;
                      document.documentElement.classList.remove('focus-native-video-fallback');
                    }
                    """,
                    settingKey: .playerMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "dynamic-prune",
            hosts: ["t.bilibili.com"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "dynamic-mask",
                    requiredSelectors: ["main", ".bili-dyn-content"],
                    optionalSelectors: ["aside.left", "aside.right", ".bili-dyn-sidebar"],
                    action: .prune,
                    css: """
                    .left-entry,
                    .right-entry,
                    .bili-header__channel,
                    aside.left,
                    aside.right,
                    .bili-dyn-sidebar,
                    .bili-dyn-sidebar__right,
                    .bili-dyn-live-users,
                    .bili-dyn-card-reserve,
                    .bili-dyn-card-common__options {
                      display: none !important;
                    }
                    """,
                    settingKey: .dynamicMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "dynamic-repair",
            hosts: ["t.bilibili.com"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "dynamic-layout",
                    requiredSelectors: ["#app", ".bili-layout", ".bili-dyn-content"],
                    optionalSelectors: ["#bili-header-container", ".bili-header", ".center-search-container"],
                    action: .repair,
                    css: """
                    html,
                    body,
                    #app {
                      width: 100% !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                    }

                    #bili-header-container,
                    .bili-header,
                    .bili-header__bar,
                    .center-search-container {
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      box-sizing: border-box !important;
                    }

                    .bili-dyn-home--member,
                    .bili-layout,
                    main,
                    .bili-dyn-content {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                    }

                    main {
                      display: block !important;
                    }

                    .bili-dyn-list__items,
                    .bili-dyn-item,
                    .bili-dyn-item__main,
                    .bili-opus-view,
                    .opus-module-content {
                      width: 100% !important;
                      max-width: 100% !important;
                      box-sizing: border-box !important;
                    }
                    """,
                    settingKey: .dynamicMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "search-prune",
            hosts: ["m.bilibili.com", "www.bilibili.com", "search.bilibili.com"],
            pathPrefixes: ["/search", "/all"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "search-mask",
                    requiredSelectors: [".search-recommend", ".search-list"],
                    optionalSelectors: [".m-bottom-app-download", ".m-nav-bottom", ".open-app"],
                    action: .prune,
                    css: """
                    .m-bottom-app-download,
                    .m-nav-bottom,
                    .search-recommend,
                    .search__download,
                    .m-search-foot-app,
                    .open-app,
                    .download-app,
                    .video-page-special-card-small,
                    .vui_header,
                    .bili-header,
                    .international-header,
                    #biliMainHeader,
                    #bili-header-container,
                    [class*="openapp"],
                    [class*="download-app"] {
                      display: none !important;
                    }
                    """,
                    settingKey: .searchMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "search-repair",
            hosts: ["m.bilibili.com", "www.bilibili.com", "search.bilibili.com"],
            pathPrefixes: ["/search", "/all"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "search-video-link-rewrite",
                    requiredSelectors: [".search-list"],
                    optionalSelectors: ["a[href*=\"/video/\"]", "a[href*=\"/bangumi/play/\"]"],
                    action: .repair,
                    css: """
                    html,
                    body,
                    #app,
                    #i_cecream,
                    main {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                      box-sizing: border-box !important;
                      background: #f5f7fb !important;
                    }

                    body {
                      padding-bottom: 36px !important;
                    }

                    .search-page,
                    .search-all-list,
                    .search-list,
                    .flow-loader,
                    .result-wrap,
                    .left-wrap,
                    .video-list,
                    .media-list,
                    .up-list,
                    .user-list,
                    .bangumi-list,
                    .film-list {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      box-sizing: border-box !important;
                    }

                    .search-page,
                    [class*="search-page"],
                    [class*="search-main"] {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      background: transparent !important;
                    }

                    .search-page,
                    .search-all-list,
                    .search-list,
                    .result-wrap,
                    .left-wrap {
                      padding-left: 16px !important;
                      padding-right: 16px !important;
                      padding-top: 0 !important;
                    }

                    [data-focus-search-input-shell] {
                      display: flex !important;
                      align-items: center !important;
                      gap: 10px !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      margin: 6px 0 8px !important;
                      padding: 4px 0 4px 14px !important;
                      box-sizing: border-box !important;
                      border: 0 !important;
                      overflow: hidden !important;
                      border-radius: 20px !important;
                      background: rgba(255, 255, 255, 0.98) !important;
                      box-shadow: 0 10px 24px rgba(15, 23, 42, 0.06) !important;
                    }

                    [data-focus-search-input-shell] input,
                    [data-focus-search-input-shell] textarea {
                      flex: 1 1 auto !important;
                      width: auto !important;
                      min-width: 0 !important;
                      min-height: 42px !important;
                      margin: 0 !important;
                      padding: 0 10px !important;
                      border: 0 !important;
                      border-radius: 0 !important;
                      background: transparent !important;
                      box-shadow: none !important;
                      color: #111827 !important;
                      font-size: 17px !important;
                      outline: none !important;
                    }

                    [data-focus-search-input-shell] button,
                    [data-focus-search-input-shell] [role="button"] {
                      min-height: 44px !important;
                      margin: 0 !important;
                      padding: 0 22px !important;
                      border: 0 !important;
                      border-radius: 0 20px 20px 0 !important;
                      background: #21a6e8 !important;
                      color: #ffffff !important;
                      font-weight: 700 !important;
                      box-shadow: none !important;
                    }

                    .search-tabs,
                    .vui_tabs,
                    .vui_tabs--navbar,
                    .vui_tabs--nav,
                    .search-page .search-input-wrap,
                    .search-page .search-input,
                    .search-page .search-bar,
                    .search-page .search-head,
                    .search-page .cancel,
                    .search-page .cancel-btn,
                    .search-page .search-condition,
                    .search-page .filter-wrap,
                    .search-page .sort-wrap,
                    .search-page .video-filter,
                    .search-page .search-filter,
                    .search-page [class*="download"],
                    .search-page [class*="openapp"],
                    .search-page [class*="app-guide"] {
                      display: none !important;
                    }

                    .search-page .search-tabs,
                    .search-page .search-menu,
                    .search-page .search-type-nav,
                    .search-page .vui_tabs--nav,
                    .search-page [class*="tab-nav"],
                    .search-page [class*="tabs-nav"],
                    .search-page [class*="tabwrap"],
                    .search-page [class*="type-nav"],
                    .search-page [class*="partition"],
                    .search-all-list .search-tabs,
                    .search-all-list .search-menu,
                    .search-all-list .search-type-nav,
                    .search-all-list .vui_tabs--nav,
                    .search-all-list [class*="tab-nav"],
                    .search-all-list [class*="tabs-nav"],
                    .search-all-list [class*="tabwrap"],
                    .search-all-list [class*="type-nav"],
                    .search-all-list [class*="partition"],
                    .search-page [role="tablist"],
                    .search-all-list [role="tablist"],
                    .search-page nav:has([role="tab"]),
                    .search-all-list nav:has([role="tab"]) {
                      display: none !important;
                    }

                    [data-focus-search-type-root] {
                      display: none !important;
                    }

                    .search-page .search-tabs::-webkit-scrollbar,
                    .search-page .search-menu::-webkit-scrollbar,
                    .search-page .search-type-nav::-webkit-scrollbar,
                    .search-page .vui_tabs--nav::-webkit-scrollbar,
                    .search-page [role="tablist"]::-webkit-scrollbar {
                      display: none !important;
                    }

                    .search-page .search-tabs > *,
                    .search-page .search-menu > *,
                    .search-page .search-type-nav > *,
                    .search-page .vui_tabs--nav > *,
                    .search-page [role="tablist"] > * {
                      flex: 0 0 auto !important;
                      min-width: 0 !important;
                      padding: 8px 12px !important;
                      border-radius: 999px !important;
                      background: #ffffff !important;
                      box-shadow: 0 6px 18px rgba(15, 23, 42, 0.05) !important;
                    }

                    .search-page [class*="condition"]:has(button),
                    .search-page [class*="condition"]:has([role="button"]),
                    .search-page [class*="sort"]:has(button),
                    .search-page [class*="sort"]:has([role="button"]),
                    .search-page [class*="filter"]:has(button),
                    .search-page [class*="filter"]:has([role="button"]),
                    .search-all-list [class*="condition"]:has(button),
                    .search-all-list [class*="condition"]:has([role="button"]),
                    .search-all-list [class*="sort"]:has(button),
                    .search-all-list [class*="sort"]:has([role="button"]),
                    .search-all-list [class*="filter"]:has(button),
                    .search-all-list [class*="filter"]:has([role="button"]) {
                      display: flex !important;
                      flex-wrap: wrap !important;
                      align-items: center !important;
                      gap: 10px !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      margin: 0 !important;
                      padding: 0 12px 12px !important;
                      background: transparent !important;
                    }

                    .search-page [class*="condition"]:has(button) > *,
                    .search-page [class*="condition"]:has([role="button"]) > *,
                    .search-page [class*="sort"]:has(button) > *,
                    .search-page [class*="sort"]:has([role="button"]) > *,
                    .search-page [class*="filter"]:has(button) > *,
                    .search-page [class*="filter"]:has([role="button"]) > *,
                    .search-all-list [class*="condition"]:has(button) > *,
                    .search-all-list [class*="condition"]:has([role="button"]) > *,
                    .search-all-list [class*="sort"]:has(button) > *,
                    .search-all-list [class*="sort"]:has([role="button"]) > *,
                    .search-all-list [class*="filter"]:has(button) > *,
                    .search-all-list [class*="filter"]:has([role="button"]) > * {
                      flex: 0 0 auto !important;
                      width: auto !important;
                      max-width: 100% !important;
                      min-width: 0 !important;
                    }

                    .search-page [class*="condition"]:has(button) button,
                    .search-page [class*="condition"]:has([role="button"]) [role="button"],
                    .search-page [class*="sort"]:has(button) button,
                    .search-page [class*="sort"]:has([role="button"]) [role="button"],
                    .search-page [class*="filter"]:has(button) button,
                    .search-page [class*="filter"]:has([role="button"]) [role="button"],
                    .search-all-list [class*="condition"]:has(button) button,
                    .search-all-list [class*="condition"]:has([role="button"]) [role="button"],
                    .search-all-list [class*="sort"]:has(button) button,
                    .search-all-list [class*="sort"]:has([role="button"]) [role="button"],
                    .search-all-list [class*="filter"]:has(button) button,
                    .search-all-list [class*="filter"]:has([role="button"]) [role="button"] {
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      width: auto !important;
                      min-height: 38px !important;
                      padding: 0 14px !important;
                      white-space: nowrap !important;
                      border-radius: 12px !important;
                      border: 1px solid #dfe7f2 !important;
                      background: #ffffff !important;
                      box-shadow: 0 4px 12px rgba(15, 23, 42, 0.04) !important;
                    }

                    .search-page [class*="condition"] .active,
                    .search-page [class*="condition"] .is-active,
                    .search-page [class*="condition"] .on,
                    .search-page [class*="sort"] .active,
                    .search-page [class*="sort"] .is-active,
                    .search-page [class*="sort"] .on,
                    .search-page [class*="filter"] .active,
                    .search-page [class*="filter"] .is-active,
                    .search-page [class*="filter"] .on,
                    .search-all-list [class*="condition"] .active,
                    .search-all-list [class*="condition"] .is-active,
                    .search-all-list [class*="condition"] .on,
                    .search-all-list [class*="sort"] .active,
                    .search-all-list [class*="sort"] .is-active,
                    .search-all-list [class*="sort"] .on,
                    .search-all-list [class*="filter"] .active,
                    .search-all-list [class*="filter"] .is-active,
                    .search-all-list [class*="filter"] .on {
                      color: #0284c7 !important;
                      border-color: #9ad7ff !important;
                      background: #eaf7ff !important;
                    }

                    [data-focus-search-filter-shell] {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 8px !important;
                      width: 100% !important;
                      max-width: 100% !important;
                      min-width: 0 !important;
                      margin: 0 0 10px !important;
                      padding: 8px 10px !important;
                      box-sizing: border-box !important;
                      border: 1px solid #e5ebf4 !important;
                      border-radius: 16px !important;
                      background: #ffffff !important;
                      box-shadow: 0 12px 30px rgba(15, 23, 42, 0.06) !important;
                    }

                    [data-focus-search-filter-row] {
                      display: grid !important;
                      grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                      gap: 10px !important;
                      width: 100% !important;
                      min-width: 0 !important;
                    }

                    [data-focus-search-filter-row][data-focus-row-kind="primary"] {
                      grid-template-columns: repeat(4, minmax(0, 1fr)) !important;
                    }

                    [data-focus-search-filter-chip] {
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      min-height: 42px !important;
                      padding: 0 10px !important;
                      border: 1px solid #dfe7f2 !important;
                      border-radius: 14px !important;
                      background: #ffffff !important;
                      color: #374151 !important;
                      box-shadow: 0 4px 12px rgba(15, 23, 42, 0.04) !important;
                      font-size: 14px !important;
                      font-weight: 600 !important;
                      line-height: 1.2 !important;
                      white-space: nowrap !important;
                      text-align: center !important;
                    }

                    [data-focus-search-filter-chip][data-focus-active="true"] {
                      color: #0284c7 !important;
                      border-color: #9ad7ff !important;
                      background: #eaf7ff !important;
                    }

                    .right-wrap,
                    .aside-wrap,
                    .search-sidebar,
                    .suggest-wrap,
                    .search-footer-app,
                    .brand-ad-list.search-all-list,
                    .search-game-card,
                    .search-special-card,
                    .search-topic-card,
                    .search-activity-card,
                    .search-brand-card,
                    .search-ad-card,
                    .video-page-special-card,
                    .video-page-special-card-small,
                    [class*="brand-ad"],
                    [class*="search-game"],
                    [class*="game-card"],
                    [class*="special-card"],
                    [class*="topic-card"],
                    [class*="activity-card"],
                    [class*="promote-card"],
                    [class*="advert-card"] {
                      display: none !important;
                    }

                    .search-list > *,
                    .result-wrap > *,
                    .left-wrap > *,
                    .video-list > *,
                    .media-list > *,
                    .live-list > *,
                    .up-list > *,
                    .user-list > *,
                    .bangumi-list > *,
                    .film-list > * {
                      width: 100% !important;
                      max-width: 100% !important;
                      min-width: 0 !important;
                    }

                    .media-list,
                    .live-list,
                    .up-list,
                    .user-list,
                    .bangumi-list,
                    .film-list {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 12px !important;
                    }

                    .up-list,
                    .user-list {
                      margin-bottom: 16px !important;
                    }

                    .bangumi-pgc-list.search-all-list {
                      margin-bottom: 18px !important;
                      padding-bottom: 12px !important;
                    }

                    .video.search-all-list {
                      margin-top: 18px !important;
                      padding-top: 0 !important;
                      border-top: 0 !important;
                    }

                    .video-list {
                      display: block !important;
                    }

                    [data-focus-search-video-grid="true"] {
                      display: grid !important;
                      grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                      gap: 8px !important;
                      align-items: start !important;
                    }

                    [data-focus-search-video-grid="true"] > [data-focus-search-video-cell="true"] {
                      display: flex !important;
                      flex-direction: column !important;
                      width: auto !important;
                      max-width: none !important;
                      min-width: 0 !important;
                      padding: 0 !important;
                      margin: 0 !important;
                      overflow: hidden !important;
                      border-radius: 18px !important;
                      background: #ffffff !important;
                      box-shadow: 0 8px 20px rgba(15, 23, 42, 0.05) !important;
                    }

                    .live-list {
                      display: grid !important;
                      grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                      gap: 8px !important;
                      align-items: start !important;
                    }

                    .live-list .live-item {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 0 !important;
                      padding: 0 !important;
                      min-height: 210px !important;
                    }

                    .live-list .live-item > :first-child {
                      grid-row: auto !important;
                      width: 100% !important;
                      min-width: 100% !important;
                      max-width: 100% !important;
                      aspect-ratio: 16 / 10 !important;
                      border-radius: 0 !important;
                    }

                    .live-list .live-item > :not(:first-child) {
                      grid-column: auto !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      padding-left: 12px !important;
                      padding-right: 12px !important;
                    }

                    .live-list .live-item [class*="cover"],
                    .live-list .live-item [class*="image"],
                    .live-list .live-item [class*="img"],
                    .live-list .live-item [class*="pic"] {
                      width: 100% !important;
                      min-width: 0 !important;
                      aspect-ratio: 16 / 10 !important;
                      overflow: hidden !important;
                      border-radius: 0 !important;
                      background: #eef2f7 !important;
                    }

                    .live-list .live-item [class*="cover"] img,
                    .live-list .live-item [class*="image"] img,
                    .live-list .live-item [class*="img"] img,
                    .live-list .live-item [class*="pic"] img,
                    .live-list .live-item [class*="cover"] picture,
                    .live-list .live-item [class*="image"] picture,
                    .live-list .live-item [class*="img"] picture,
                    .live-list .live-item [class*="pic"] picture {
                      width: 100% !important;
                      height: 100% !important;
                      object-fit: cover !important;
                      border-radius: 0 !important;
                    }

                    .live-list .live-item button,
                    .live-list .live-item [role="button"],
                    .live-list .live-item [class*="button"],
                    .live-list .live-item [class*="btn"],
                    .live-list .live-item [class*="follow"],
                    .live-list .live-item [class*="reserve"],
                    .live-list .live-item [class*="appointment"],
                    .live-list .live-item [class*="progress"],
                    .live-list .live-item [class*="action"],
                    .live-list .live-item [class*="interact"],
                    .live-list .live-item [class*="lottery"],
                    .live-list .live-item [class*="pk"] {
                      display: none !important;
                    }

                    .live-list .live-item [class*="button"]::before,
                    .live-list .live-item [class*="button"]::after,
                    .live-list .live-item [class*="btn"]::before,
                    .live-list .live-item [class*="btn"]::after,
                    .live-list .live-item [class*="follow"]::before,
                    .live-list .live-item [class*="follow"]::after,
                    .live-list .live-item [class*="reserve"]::before,
                    .live-list .live-item [class*="reserve"]::after,
                    .live-list .live-item [class*="appointment"]::before,
                    .live-list .live-item [class*="appointment"]::after,
                    .live-list .live-item [class*="progress"]::before,
                    .live-list .live-item [class*="progress"]::after {
                      display: none !important;
                      content: none !important;
                    }

                    .live-list .live-item [class*="progress"],
                    .live-list .live-item [class*="reserve"],
                    .live-list .live-item [class*="follow"],
                    .live-list .live-item [class*="button"],
                    .live-list .live-item [class*="btn"] {
                      min-height: 0 !important;
                      max-height: 0 !important;
                      border: 0 !important;
                      opacity: 0 !important;
                      overflow: hidden !important;
                    }

                    [data-focus-search-up-card="true"] {
                      display: grid !important;
                      grid-template-columns: 72px minmax(0, 1fr) !important;
                      grid-auto-rows: min-content !important;
                      align-content: start !important;
                      align-items: start !important;
                      column-gap: 12px !important;
                      row-gap: 6px !important;
                      padding: 16px !important;
                    }

                    [data-focus-search-up-card="true"] > :first-child {
                      grid-row: 1 / span 4 !important;
                      width: 72px !important;
                      min-width: 72px !important;
                      max-width: 72px !important;
                      overflow: hidden !important;
                      border-radius: 18px !important;
                    }

                    [data-focus-search-up-card="true"] > :not(:first-child) {
                      grid-column: 2 !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      padding-left: 0 !important;
                      padding-right: 0 !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-strip="true"] {
                      grid-column: 1 / -1 !important;
                      display: flex !important;
                      gap: 10px !important;
                      overflow-x: auto !important;
                      padding-top: 8px !important;
                      padding-bottom: 2px !important;
                      margin-top: 2px !important;
                      scroll-snap-type: x proximity !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-strip="true"]::-webkit-scrollbar {
                      display: none !important;
                    }

                    .up-list .up-item > div:has(a[href*="/video/"]):has(img),
                    .up-list .up-item > section:has(a[href*="/video/"]):has(img),
                    .up-list .up-item > ul:has(a[href*="/video/"]):has(img),
                    .user-list .user-item > div:has(a[href*="/video/"]):has(img),
                    .user-list .user-item > section:has(a[href*="/video/"]):has(img),
                    .user-list .user-item > ul:has(a[href*="/video/"]):has(img) {
                      grid-column: 1 / -1 !important;
                      display: flex !important;
                      gap: 10px !important;
                      overflow-x: auto !important;
                      padding-top: 8px !important;
                      padding-bottom: 2px !important;
                      margin-top: 2px !important;
                      scroll-snap-type: x proximity !important;
                    }

                    .up-list .up-item > div:has(a[href*="/video/"]):has(img)::-webkit-scrollbar,
                    .up-list .up-item > section:has(a[href*="/video/"]):has(img)::-webkit-scrollbar,
                    .up-list .up-item > ul:has(a[href*="/video/"]):has(img)::-webkit-scrollbar,
                    .user-list .user-item > div:has(a[href*="/video/"]):has(img)::-webkit-scrollbar,
                    .user-list .user-item > section:has(a[href*="/video/"]):has(img)::-webkit-scrollbar,
                    .user-list .user-item > ul:has(a[href*="/video/"]):has(img)::-webkit-scrollbar {
                      display: none !important;
                    }

                    .up-list .up-item > div:has(a[href*="/video/"]):has(img) > *,
                    .up-list .up-item > section:has(a[href*="/video/"]):has(img) > *,
                    .up-list .up-item > ul:has(a[href*="/video/"]):has(img) > *,
                    .user-list .user-item > div:has(a[href*="/video/"]):has(img) > *,
                    .user-list .user-item > section:has(a[href*="/video/"]):has(img) > *,
                    .user-list .user-item > ul:has(a[href*="/video/"]):has(img) > * {
                      flex: 0 0 148px !important;
                      width: 148px !important;
                      min-width: 148px !important;
                      overflow: hidden !important;
                      border-radius: 16px !important;
                      background: #f8fafc !important;
                      box-shadow: 0 8px 18px rgba(15, 23, 42, 0.05) !important;
                      scroll-snap-align: start !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-video="true"] {
                      flex: 0 0 148px !important;
                      width: 148px !important;
                      min-width: 148px !important;
                      overflow: hidden !important;
                      border-radius: 16px !important;
                      background: #f8fafc !important;
                      box-shadow: 0 8px 18px rgba(15, 23, 42, 0.05) !important;
                      scroll-snap-align: start !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-video-cover="true"] {
                      position: relative !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      aspect-ratio: 16 / 10 !important;
                      overflow: hidden !important;
                      background: #eef2f7 !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-video-cover="true"] img,
                    [data-focus-search-up-card="true"] [data-focus-search-up-video-cover="true"] picture,
                    [data-focus-search-up-card="true"] [data-focus-search-up-video-cover="true"] video,
                    [data-focus-search-up-card="true"] [data-focus-search-up-video-cover="true"] canvas {
                      width: 100% !important;
                      height: 100% !important;
                      object-fit: cover !important;
                      border-radius: 0 !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-video-title="true"] {
                      display: -webkit-box !important;
                      margin: 8px 10px 0 !important;
                      line-height: 1.45 !important;
                      font-size: 13px !important;
                      font-weight: 600 !important;
                      color: #111827 !important;
                      -webkit-box-orient: vertical !important;
                      -webkit-line-clamp: 2 !important;
                      overflow: hidden !important;
                    }

                    [data-focus-search-up-card="true"] [data-focus-search-up-video-meta="true"] {
                      display: block !important;
                      margin: 4px 10px 10px !important;
                      line-height: 1.35 !important;
                      font-size: 12px !important;
                      color: #6b7280 !important;
                      white-space: nowrap !important;
                      overflow: hidden !important;
                      text-overflow: ellipsis !important;
                    }

                    [data-focus-search-video-content-root="true"] {
                      display: flex !important;
                      flex-direction: column !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      min-height: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      color: inherit !important;
                      text-decoration: none !important;
                      background: transparent !important;
                      box-sizing: border-box !important;
                    }

                    [data-focus-search-video-content-root="true"] > * {
                      min-width: 0 !important;
                      max-width: 100% !important;
                    }

                    .video-item,
                    .bili-video-card,
                    .live-item,
                    .up-item,
                    .user-item,
                    .result-item,
                    .media-item,
                    .bangumi-item,
                    .film-item {
                      display: block !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 14px !important;
                      overflow: hidden !important;
                      border-radius: 18px !important;
                      background: #ffffff !important;
                      box-shadow: 0 10px 26px rgba(15, 23, 42, 0.06) !important;
                      box-sizing: border-box !important;
                    }

                    .bangumi-pgc-list .media-item {
                      padding: 14px !important;
                    }

                    .video-item > *,
                    .bili-video-card > *,
                    .live-item > *,
                    .up-item > *,
                    .user-item > *,
                    .result-item > *,
                    .media-item > *,
                    .bangumi-item > *,
                    .film-item > * {
                      min-width: 0 !important;
                      max-width: 100% !important;
                    }

                    .media-list .media-item,
                    .bangumi-list .bangumi-item,
                    .film-list .film-item,
                    .up-list .up-item,
                    .user-list .user-item {
                      display: grid !important;
                      grid-template-columns: 112px minmax(0, 1fr) !important;
                      grid-auto-rows: min-content !important;
                      align-content: start !important;
                      align-items: start !important;
                      column-gap: 14px !important;
                      row-gap: 6px !important;
                    }

                    .up-list .up-item,
                    .user-list .user-item {
                      grid-template-columns: 88px minmax(0, 1fr) !important;
                      column-gap: 12px !important;
                      row-gap: 8px !important;
                      padding: 16px !important;
                    }

                    .media-list .media-item > :first-child,
                    .bangumi-list .bangumi-item > :first-child,
                    .film-list .film-item > :first-child,
                    .up-list .up-item > :first-child,
                    .user-list .user-item > :first-child {
                      grid-row: 1 / span 10 !important;
                      width: 112px !important;
                      min-width: 112px !important;
                      max-width: 112px !important;
                      align-self: stretch !important;
                      overflow: hidden !important;
                      border-radius: 16px !important;
                    }

                    .up-list .up-item > :first-child,
                    .user-list .user-item > :first-child {
                      width: 88px !important;
                      min-width: 88px !important;
                      max-width: 88px !important;
                      border-radius: 20px !important;
                    }

                    .media-list .media-item > :not(:first-child),
                    .bangumi-list .bangumi-item > :not(:first-child),
                    .film-list .film-item > :not(:first-child),
                    .up-list .up-item > :not(:first-child),
                    .user-list .user-item > :not(:first-child) {
                      grid-column: 2 !important;
                      width: 100% !important;
                      min-width: 0 !important;
                    }

                    .up-list .up-item > :not(:first-child),
                    .user-list .user-item > :not(:first-child) {
                      padding-left: 0 !important;
                      padding-right: 0 !important;
                    }

                    .up-list .up-item button,
                    .up-list .up-item [role="button"],
                    .up-list .up-item [class*="follow"],
                    .user-list .user-item button,
                    .user-list .user-item [role="button"],
                    .user-list .user-item [class*="follow"] {
                      justify-self: start !important;
                      width: auto !important;
                      max-width: 100% !important;
                      min-height: 36px !important;
                      margin-top: 2px !important;
                      padding: 0 14px !important;
                      border-radius: 12px !important;
                    }

                    .bangumi-item [class*="badge"],
                    .film-item [class*="badge"],
                    .bangumi-item [class*="member"],
                    .film-item [class*="member"] {
                      max-width: 100% !important;
                    }

                    .video-list .bili-video-card__no-interest {
                      display: none !important;
                    }

                    .video-item [class*="title"],
                    .bili-video-card [class*="title"],
                    .result-item [class*="title"],
                    .media-item [class*="title"],
                    .bangumi-item [class*="title"],
                    .film-item [class*="title"],
                    .live-item [class*="title"],
                    .up-item [class*="title"],
                    .user-item [class*="title"] {
                      margin-top: 8px !important;
                      margin-bottom: 0 !important;
                      padding-left: 4px !important;
                      padding-right: 4px !important;
                      line-height: 1.45 !important;
                      font-size: 17px !important;
                      font-weight: 600 !important;
                      color: #111827 !important;
                    }

                    .up-item [class*="title"],
                    .user-item [class*="title"] {
                      margin-top: 0 !important;
                      font-size: 18px !important;
                    }

                    .video-item [class*="desc"],
                    .video-item [class*="info"],
                    .video-item [class*="meta"],
                    .bili-video-card [class*="desc"],
                    .bili-video-card [class*="info"],
                    .bili-video-card [class*="meta"],
                    .result-item [class*="desc"],
                    .result-item [class*="info"],
                    .result-item [class*="meta"],
                    .media-item [class*="desc"],
                    .media-item [class*="info"],
                    .media-item [class*="meta"],
                    .bangumi-item [class*="desc"],
                    .bangumi-item [class*="info"],
                    .bangumi-item [class*="meta"],
                    .film-item [class*="desc"],
                    .film-item [class*="info"],
                    .film-item [class*="meta"],
                    .live-item [class*="desc"],
                    .live-item [class*="info"],
                    .live-item [class*="meta"],
                    .up-item [class*="desc"],
                    .up-item [class*="info"],
                    .up-item [class*="meta"],
                    .user-item [class*="desc"],
                    .user-item [class*="info"],
                    .user-item [class*="meta"] {
                      margin-top: 6px !important;
                      margin-bottom: 0 !important;
                      padding-left: 4px !important;
                      padding-right: 4px !important;
                      line-height: 1.5 !important;
                      color: #6b7280 !important;
                    }

                    .up-item [class*="desc"],
                    .up-item [class*="info"],
                    .up-item [class*="meta"],
                    .user-item [class*="desc"],
                    .user-item [class*="info"],
                    .user-item [class*="meta"] {
                      padding-left: 0 !important;
                      padding-right: 0 !important;
                    }

                    [data-focus-search-video-content-root="true"] > [data-focus-search-video-cover="true"] {
                      order: 0 !important;
                    }

                    [data-focus-search-video-content-root="true"] > [data-focus-search-video-info-shell="true"] {
                      order: 1 !important;
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 4px !important;
                      padding: 10px 12px 12px !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-cover="true"] {
                      position: relative !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      aspect-ratio: 16 / 10 !important;
                      overflow: hidden !important;
                      margin: 0 !important;
                      border-radius: 0 !important;
                      background: #eef2f7 !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-cover="true"] img,
                    [data-focus-search-video-content-root="true"] [data-focus-search-video-cover="true"] picture,
                    [data-focus-search-video-content-root="true"] [data-focus-search-video-cover="true"] video,
                    [data-focus-search-video-content-root="true"] [data-focus-search-video-cover="true"] canvas {
                      width: 100% !important;
                      height: 100% !important;
                      object-fit: cover !important;
                      border-radius: 0 !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-secondary-stat="true"] {
                      display: none !important;
                    }

                    [data-focus-search-video-content-root="true"] button,
                    [data-focus-search-video-content-root="true"] [role="button"],
                    [data-focus-search-video-content-root="true"] [class*="button"],
                    [data-focus-search-video-content-root="true"] [class*="btn"],
                    [data-focus-search-video-content-root="true"] [class*="follow"],
                    [data-focus-search-video-content-root="true"] [class*="reserve"],
                    [data-focus-search-video-content-root="true"] [class*="progress"],
                    [data-focus-search-video-content-root="true"] [class*="attend"],
                    [data-focus-search-video-content-root="true"] [class*="appointment"] {
                      display: none !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-title="true"] {
                      margin-top: 9px !important;
                      margin-bottom: 0 !important;
                      line-height: 1.4 !important;
                      font-size: 15px !important;
                      font-weight: 650 !important;
                      color: #111827 !important;
                      display: -webkit-box !important;
                      -webkit-box-orient: vertical !important;
                      -webkit-line-clamp: 2 !important;
                      overflow: hidden !important;
                    }

                    [data-focus-search-video-content-root="true"] > [data-focus-search-video-title="true"] {
                      order: 1 !important;
                      padding-left: 12px !important;
                      padding-right: 12px !important;
                    }

                    [data-focus-search-video-content-root="true"] > [data-focus-search-video-meta="true"] {
                      order: 2 !important;
                      padding-left: 12px !important;
                      padding-right: 12px !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-info-shell="true"] [data-focus-search-video-title="true"] {
                      margin-top: 0 !important;
                    }

                    [data-focus-search-video-content-root="true"] [data-focus-search-video-meta="true"] {
                      display: block !important;
                      margin-top: 4px !important;
                      margin-bottom: 0 !important;
                      line-height: 1.35 !important;
                      font-size: 12px !important;
                      color: #6b7280 !important;
                      white-space: nowrap !important;
                      overflow: hidden !important;
                      text-overflow: ellipsis !important;
                    }

                    .video-list > [data-focus-search-video-cell="true"],
                    [data-focus-search-video-grid="true"] > [data-focus-search-video-cell="true"] {
                      padding: 0 0 10px !important;
                      border-radius: 18px !important;
                      background: #ffffff !important;
                    }

                    img,
                    video {
                      max-width: 100% !important;
                      height: auto !important;
                      border-radius: 14px !important;
                      display: block !important;
                    }

                    a {
                      color: inherit !important;
                      text-decoration: none !important;
                    }

                    .search-page *,
                    .search-list *,
                    .result-wrap * {
                      word-break: break-word !important;
                      box-sizing: border-box !important;
                    }
                    """,
                    script: """
                    const state = helpers.featureState;
                    const videoPattern = /\\/video\\/|\\/bangumi\\/play\\//;

                    const rewriteAnchor = (anchor) => {
                      if (!anchor || !anchor.href) {
                        return;
                      }

                      const canonicalURL = extractCanonicalVideoURL(anchor);
                      if (!canonicalURL) {
                        return;
                      }

                      if (canonicalURL !== anchor.href) {
                        anchor.href = canonicalURL;
                      }
                      anchor.removeAttribute('target');
                    };

                    const candidateKeys = ['href', 'data-href', 'data-url', 'data-link', 'data-target-url', 'data-jump-url', 'data-report-click', 'data-arcurl', 'data-target'];
                    const interactiveSelector = 'button, a, [role="button"], [role="tab"], input, select, label';
                    const normalizeLabel = (value) => String(value || '').replace(/\\s+/g, '').replace(/[：:]/g, '');
                    const primaryFilterLabels = ['综合排序', '最多播放', '最新发布', '最多弹幕', '最多收藏', '更多筛选'];
                    const collapsedPrimaryLabels = ['综合排序', '最多播放', '最新发布'];
                    const extendedPrimaryLabels = ['最多弹幕', '最多收藏'];
                    const dateFilterLabels = ['全部日期', '最近一天', '最近三天', '最近一周', '最近一个月', '最近半年', '开始日期', '结束日期'];
                    const durationFilterLabels = ['全部时长', '10分钟以下', '10-30分钟', '30-60分钟', '60分钟以上'];
                    const searchFilterKeywords = primaryFilterLabels.concat(dateFilterLabels, durationFilterLabels);
                    const searchTypeLabels = ['综合', '视频', '番剧', '影视', '直播', '用户', '专栏'];
                    const promotedSearchKeywords = ['广告', '立即预约', '立即下载', '游戏下载', '打开app', '打开应用', '福利', '礼包', '攻略站', '游戏中心'];
                    const debugSearch = (message, extra) => {
                      helpers.postDebug(message, extra || null);
                    };
                    const incrementDebugCounter = (key) => {
                      state[key] = (state[key] || 0) + 1;
                      return state[key];
                    };
                    const installSearchScrollGuard = () => {
                      if (state.searchScrollGuardInstalled) {
                        return;
                      }

                      state.searchScrollGuardInstalled = true;
                      const markScroll = () => {
                        state.lastSearchScrollAt = Date.now();
                      };

                      window.addEventListener('scroll', markScroll, { passive: true, capture: true });
                      document.addEventListener('touchmove', markScroll, { passive: true, capture: true });
                      document.addEventListener('wheel', markScroll, { passive: true, capture: true });
                    };

                    const wasRecentScrollGesture = () => {
                      return Date.now() - (state.lastSearchScrollAt || 0) < 240;
                    };

                    const extractCanonicalFromParsedURL = (parsedURL) => {
                      if (!parsedURL) {
                        return null;
                      }

                      const host = String(parsedURL.hostname || '').toLowerCase();
                      const path = String(parsedURL.pathname || '').toLowerCase();
                      const isStandardBilibiliHost = host === 'www.bilibili.com' || host === 'bilibili.com' || host === 'm.bilibili.com';
                      if (!isStandardBilibiliHost) {
                        return null;
                      }

                      if (videoPattern.test(path)) {
                        parsedURL.protocol = 'https:';
                        parsedURL.hostname = 'www.bilibili.com';
                        if (path.indexOf('/video/') === 0 && !parsedURL.pathname.endsWith('/')) {
                          parsedURL.pathname += '/';
                        }
                        if (path.indexOf('/video/') === 0) {
                          const preservedNames = new Set(['p', 't', 'start_progress', 'start_progress_ms', 'spm_id_from', 'from_spmid', 'from_source']);
                          Array.from(parsedURL.searchParams.keys()).forEach((key) => {
                            if (!preservedNames.has(String(key).toLowerCase())) {
                              parsedURL.searchParams.delete(key);
                            }
                          });
                        }
                        return parsedURL.toString();
                      }

                      if (/^\\/blackboard\\/html5(?:mobile)?player\\.html$/.test(path)) {
                        const bvid = parsedURL.searchParams.get('bvid');
                        const aid = parsedURL.searchParams.get('aid') || parsedURL.searchParams.get('avid');
                        if (bvid) {
                          parsedURL.protocol = 'https:';
                          parsedURL.hostname = 'www.bilibili.com';
                          parsedURL.pathname = '/video/' + bvid;
                          if (!parsedURL.pathname.endsWith('/')) {
                            parsedURL.pathname += '/';
                          }
                          parsedURL.searchParams.delete('bvid');
                          parsedURL.searchParams.delete('aid');
                          parsedURL.searchParams.delete('avid');
                          return parsedURL.toString();
                        }

                        if (aid) {
                          parsedURL.protocol = 'https:';
                          parsedURL.hostname = 'www.bilibili.com';
                          parsedURL.pathname = '/video/av' + aid;
                          if (!parsedURL.pathname.endsWith('/')) {
                            parsedURL.pathname += '/';
                          }
                          parsedURL.searchParams.delete('bvid');
                          parsedURL.searchParams.delete('aid');
                          parsedURL.searchParams.delete('avid');
                          return parsedURL.toString();
                        }
                      }

                      return null;
                    };

                    const extractCanonicalFromRawValue = (rawValue) => {
                      if (typeof rawValue !== 'string') {
                        return null;
                      }

                      const trimmed = rawValue.trim();
                      if (!trimmed) {
                        return null;
                      }

                      try {
                        const parsedURL = new URL(trimmed, location.href);
                        const canonicalURL = extractCanonicalFromParsedURL(parsedURL);
                        if (canonicalURL) {
                          return canonicalURL;
                        }
                      } catch (_) {}

                      const directURL = helpers.canonicalizeBilibiliURL(trimmed);
                      if (directURL && videoPattern.test(directURL)) {
                        return directURL;
                      }

                      const blackboardMatch = trimmed.match(/https?:\\/\\/(?:www\\.|m\\.)?bilibili\\.com\\/blackboard\\/html5(?:mobile)?player\\.html[^\\s"'<>]*/i);
                      if (blackboardMatch) {
                        try {
                          const canonicalURL = extractCanonicalFromParsedURL(new URL(blackboardMatch[0]));
                          if (canonicalURL) {
                            return canonicalURL;
                          }
                        } catch (_) {}
                      }

                      const absoluteMatch = trimmed.match(/https?:\\/\\/(?:www\\.|m\\.)?bilibili\\.com\\/(?:video\\/BV[0-9A-Za-z]{10}|bangumi\\/play\\/(?:ep|ss)\\d+)/i);
                      if (absoluteMatch) {
                        return helpers.canonicalizeBilibiliURL(absoluteMatch[0]);
                      }

                      const relativeMatch = trimmed.match(/\\/(?:video\\/BV[0-9A-Za-z]{10}|bangumi\\/play\\/(?:ep|ss)\\d+)/i);
                      if (relativeMatch) {
                        return helpers.canonicalizeBilibiliURL(relativeMatch[0]);
                      }

                      const bvidMatch = trimmed.match(/BV[0-9A-Za-z]{10}/);
                      if (bvidMatch) {
                        return 'https://www.bilibili.com/video/' + bvidMatch[0] + '/';
                      }

                      const aidMatch = trimmed.match(/(?:aid|avid)=([0-9]+)/i);
                      if (aidMatch) {
                        return 'https://www.bilibili.com/video/av' + aidMatch[1] + '/';
                      }

                      return null;
                    };

                    const extractCanonicalVideoURL = (node) => {
                      if (!node || node === document || node === window) {
                        return null;
                      }

                      if (node.href) {
                        const canonicalURL = extractCanonicalFromRawValue(node.href);
                        if (canonicalURL) {
                          return canonicalURL;
                        }
                      }

                      if (node.getAttribute) {
                        for (const key of candidateKeys) {
                          const rawValue = node.getAttribute(key);
                          if (!rawValue) {
                            continue;
                          }
                          const canonicalURL = extractCanonicalFromRawValue(rawValue);
                          if (canonicalURL) {
                            return canonicalURL;
                          }
                        }
                      }

                      if (node.dataset) {
                        for (const value of Object.values(node.dataset)) {
                          if (typeof value !== 'string') {
                            continue;
                          }
                          const canonicalURL = extractCanonicalFromRawValue(value);
                          if (canonicalURL) {
                            return canonicalURL;
                          }
                        }
                      }

                      return null;
                    };

                    const rewriteDatasetURL = (node, key) => {
                      const currentValue = node.getAttribute(key);
                      if (!currentValue) {
                        return null;
                      }

                      const canonicalURL = extractCanonicalFromRawValue(currentValue);
                      if (canonicalURL && canonicalURL !== currentValue) {
                        node.setAttribute(key, canonicalURL);
                      }
                      return canonicalURL;
                    };

                    const rewriteAll = () => {
                      document.querySelectorAll('a[href*="/video/"], a[href*="/bangumi/play/"]').forEach(rewriteAnchor);
                      document.querySelectorAll('[data-href], [data-url], [data-link], [data-target-url], [data-jump-url], [data-report-click], [data-arcurl], [data-target]').forEach((node) => {
                        candidateKeys.forEach((key) => rewriteDatasetURL(node, key));
                      });
                      document.querySelectorAll('[href]').forEach(rewriteAnchor);
                    };

                    const isNodeVisible = (node) => {
                      if (!node || !node.getBoundingClientRect) {
                        return false;
                      }

                      const rect = node.getBoundingClientRect();
                      const style = window.getComputedStyle(node);
                      return rect.width > 40
                        && rect.height > 20
                        && style.display !== 'none'
                        && style.visibility !== 'hidden'
                        && style.opacity !== '0';
                    };

                    const isRenderableContainer = (node) => {
                      if (!node || !node.isConnected) {
                        return false;
                      }

                      const style = window.getComputedStyle(node);
                      return style.display !== 'none'
                        && style.visibility !== 'hidden'
                        && style.opacity !== '0'
                        && node.childElementCount > 0;
                    };

                    const findSearchInputElements = () => {
                      if (state.searchInputNode?.isConnected && state.searchInputShell?.isConnected) {
                        return {
                          input: state.searchInputNode,
                          shell: state.searchInputShell
                        };
                      }

                      const input = Array.from(document.querySelectorAll('input[type="search"], input[type="text"], input:not([type]), textarea'))
                        .filter((node) => isNodeVisible(node))
                        .filter((node) => {
                          const rect = node.getBoundingClientRect();
                          return rect.top < Math.max(window.innerHeight * 0.4, 260);
                        })
                        .sort((left, right) => left.getBoundingClientRect().top - right.getBoundingClientRect().top)[0] || null;

                      if (!input) {
                        return null;
                      }

                      let shell = input.closest('form, section, div');
                      while (shell && shell !== document.body) {
                        const rect = shell.getBoundingClientRect();
                        const interactiveCount = shell.querySelectorAll('input, button, [role="button"], textarea').length;
                        if (rect.width > window.innerWidth * 0.72 && rect.height < 120 && interactiveCount >= 2) {
                          break;
                        }
                        shell = shell.parentElement;
                      }

                      shell = shell || input.parentElement;
                      if (!shell) {
                        return null;
                      }

                      state.searchInputNode = input;
                      state.searchInputShell = shell;
                      return { input, shell };
                    };

                    const decorateSearchInput = () => {
                      const resolved = findSearchInputElements();
                      if (!resolved) {
                        return;
                      }

                      const { input, shell } = resolved;
                      shell.setAttribute('data-focus-search-input-shell', 'true');
                      input.setAttribute('data-focus-search-input', 'true');

                      const submit = shell.querySelector('button, [role="button"]');
                      if (submit) {
                        submit.setAttribute('data-focus-search-submit', 'true');
                      }
                    };

                    const promotedSearchRootSelector = '.video-list, .media-list, .live-list, .up-list, .user-list, .bangumi-list, .film-list';

                    const hidePromotedSearchBlocks = () => {
                      Array.from(document.querySelectorAll('.search-list, .search-all-list, .result-wrap, .left-wrap, main'))
                        .filter(isRenderableContainer)
                        .forEach((root) => {
                          Array.from(root.children || []).forEach((node) => {
                            if (!node || node.nodeType !== 1) {
                              return;
                            }

                            if (node.matches?.(promotedSearchRootSelector) || node.querySelector?.(promotedSearchRootSelector)) {
                              return;
                            }

                            if (node.hasAttribute?.('data-focus-search-filter-shell')
                              || node.hasAttribute?.('data-focus-search-input-shell')
                              || node.querySelector?.('[data-focus-search-filter-shell], [data-focus-search-input-shell]')) {
                              return;
                            }

                            const className = String(node.className || '').toLowerCase();
                            const normalizedText = normalizeLabel(node.textContent);
                            const hasLargeMedia = Array.from(node.querySelectorAll?.('img, picture, video, canvas') || []).some((mediaNode) => {
                              const rect = mediaNode.getBoundingClientRect?.();
                              return rect && rect.width >= 120 && rect.height >= 72;
                            });
                            const promotedByClass = /(?:^|\\s|-|_)(?:ad|advert|game|special|topic|activity|brand|promote)(?:$|\\s|-|_)/i.test(className);
                            const promotedByText = promotedSearchKeywords.some((keyword) => normalizedText.includes(normalizeLabel(keyword)));

                            if ((promotedByClass || promotedByText) && hasLargeMedia) {
                              node.setAttribute('data-focus-search-promoted', 'true');
                              node.style.setProperty('display', 'none', 'important');
                            }
                          });
                        });
                    };

                    const searchVideoMarkerAttributes = [
                      'data-focus-search-video-grid',
                      'data-focus-search-video-cell',
                      'data-focus-search-video-card',
                      'data-focus-search-video-content-root',
                      'data-focus-search-video-cover',
                      'data-focus-search-video-target',
                      'data-focus-search-video-secondary-stat',
                      'data-focus-search-video-info-shell',
                      'data-focus-search-video-title',
                      'data-focus-search-video-meta',
                      'data-focus-search-up-card',
                      'data-focus-search-up-strip',
                      'data-focus-search-up-video',
                      'data-focus-search-up-video-target',
                      'data-focus-search-up-video-cover',
                      'data-focus-search-up-video-title',
                      'data-focus-search-up-video-meta'
                    ];
                    const searchVideoCardSelector = '.video-item, .bili-video-card, .result-item, article, li, [class*="video-card"]';

                    const clearSearchVideoMarkers = () => {
                      searchVideoMarkerAttributes.forEach((attributeName) => {
                        document.querySelectorAll('[' + attributeName + ']').forEach((node) => {
                          node.removeAttribute(attributeName);
                        });
                      });
                    };

                    const findChildWithinContainer = (container, node) => {
                      let currentNode = node && node.nodeType === 1 ? node : node?.parentElement;
                      let directChild = null;

                      while (currentNode && currentNode !== container) {
                        directChild = currentNode;
                        currentNode = currentNode.parentElement;
                      }

                      return currentNode === container ? directChild : null;
                    };

                    const findClosestAncestorWithinContainer = (container, node, selector) => {
                      let currentNode = node && node.nodeType === 1 ? node : node?.parentElement;

                      while (currentNode && currentNode !== container) {
                        if (currentNode.matches?.(selector)) {
                          return currentNode;
                        }

                        currentNode = currentNode.parentElement;
                      }

                      return null;
                    };

                    const searchVideoInteractiveSelector = 'a[href], [data-href], [data-url], [data-link], [data-target-url], [data-jump-url], [data-report-click], [data-arcurl], [data-target]';

                    const resolveSearchVideoContentRoot = (cell, coverNode, titleNode) => {
                      const candidateNodes = [titleNode, coverNode]
                        .filter(Boolean)
                        .map((node) => findClosestAncestorWithinContainer(cell, node, searchVideoInteractiveSelector))
                        .filter(Boolean);
                      const matchingCandidate = candidateNodes.find((node) => !!extractCanonicalVideoURL(node));
                      if (matchingCandidate) {
                        return matchingCandidate;
                      }

                      return Array.from(cell.querySelectorAll(searchVideoInteractiveSelector)).find((node) => {
                        return !!extractCanonicalVideoURL(node);
                      }) || cell;
                    };

                    const installSearchVideoNavigationInterceptor = () => {
                      if (state.searchVideoNavigationInterceptorInstalled) {
                        return;
                      }

                      installSearchScrollGuard();
                      document.addEventListener('click', (event) => {
                        const trigger = event.target?.closest?.('[data-focus-search-video-target]');
                        const targetURL = trigger?.getAttribute?.('data-focus-search-video-target');
                        if (!targetURL) {
                          return;
                        }

                        if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                          return;
                        }

                        if (wasRecentScrollGesture()) {
                          return;
                        }

                        if (location.href === targetURL) {
                          return;
                        }

                        debugSearch('searchVideoClickIntercept', {
                          targetURL,
                          triggerTag: trigger?.tagName || null,
                          triggerClass: String(trigger?.className || '').slice(0, 160),
                          pageURL: location.href
                        });

                        event.preventDefault();
                        event.stopPropagation();
                        event.stopImmediatePropagation?.();

                        try {
                          window.location.assign(targetURL);
                        } catch (_) {
                          location.href = targetURL;
                        }
                      }, true);

                      state.searchVideoNavigationInterceptorInstalled = true;
                    };

                    const markSecondaryCoverStats = (coverShell) => {
                      if (!coverShell) {
                        return;
                      }

                      const logSecondaryStatSample = (strategy, items, removedItems) => {
                        if (state.searchVideoStatSampleLogged) {
                          return;
                        }

                        state.searchVideoStatSampleLogged = true;
                        debugSearch('searchVideoStatSample', {
                          strategy,
                          items: items.filter(Boolean).slice(0, 6).join(' | '),
                          removedItems: removedItems.filter(Boolean).slice(0, 4).join(' | ')
                        });
                      };

                      const coverRect = coverShell.getBoundingClientRect();
                      if (coverRect.width < 80 || coverRect.height < 60) {
                        return;
                      }

                      const isStatLikeText = (text) => {
                        return /\\d/.test(text) || /万|亿|k|m/i.test(text) || /^(?:\\d+:)?\\d{1,2}:\\d{2}$/.test(text);
                      };

                      const candidateContainer = Array.from(coverShell.querySelectorAll('div, ul, ol, section, article, a'))
                        .map((node) => {
                          const rect = node.getBoundingClientRect();
                          const visibleChildren = Array.from(node.children)
                            .filter((child) => isNodeVisible(child))
                            .filter((child) => !child.querySelector('img, picture, video, canvas'))
                            .map((child) => {
                              const text = normalizeLabel(child.textContent);
                              return {
                                node: child,
                                text,
                                rect: child.getBoundingClientRect()
                              };
                            })
                            .filter(({ text, rect }) => !!text && text.length <= 16 && rect.width > 8 && rect.height > 8 && isStatLikeText(text));

                          return {
                            node,
                            rect,
                            visibleChildren
                          };
                        })
                        .filter(({ rect, visibleChildren }) => {
                          const nearBottom = rect.bottom >= coverRect.bottom - Math.min(coverRect.height * 0.42, 48);
                          return nearBottom && visibleChildren.length >= 3 && visibleChildren.length <= 4;
                        })
                        .sort((left, right) => {
                          if (left.visibleChildren.length != right.visibleChildren.length) {
                            return right.visibleChildren.length - left.visibleChildren.length;
                          }

                          return right.rect.bottom - left.rect.bottom;
                        })[0] || null;

                      if (candidateContainer) {
                        const orderedChildren = candidateContainer.visibleChildren.sort((left, right) => left.rect.left - right.rect.left);
                        const durationChild = [...orderedChildren].reverse().find(({ text }) => /^(?:\\d+:)?\\d{1,2}:\\d{2}$/.test(text));
                        const removableChildren = orderedChildren.filter(({ node }) => node !== orderedChildren[0].node && node !== durationChild?.node);

                        removableChildren.forEach(({ node }) => {
                          node.setAttribute('data-focus-search-video-secondary-stat', 'true');
                        });
                        logSecondaryStatSample(
                          'candidateContainer',
                          orderedChildren.map(({ text }) => text),
                          removableChildren.map(({ text }) => text)
                        );
                        return;
                      }

                      const fallbackContainer = Array.from(coverShell.querySelectorAll('div, ul, ol, section, article, a, p, span'))
                        .map((node) => {
                          const rect = node.getBoundingClientRect();
                          const directChildren = Array.from(node.children)
                            .filter((child) => isNodeVisible(child))
                            .map((child) => ({
                              node: child,
                              text: normalizeLabel(child.textContent),
                              rect: child.getBoundingClientRect()
                            }))
                            .filter(({ rect, text }) => rect.width > 8 && rect.height > 8 && !!text);
                          const statChildren = directChildren.filter(({ text }) => isStatLikeText(text) || text.length <= 24 && /播放|观看|弹幕|评论/.test(text));
                          return {
                            node,
                            rect,
                            statChildren
                          };
                        })
                        .filter(({ rect, statChildren }) => {
                          const nearBottom = rect.bottom >= coverRect.bottom - Math.min(coverRect.height * 0.42, 48);
                          return nearBottom && statChildren.length >= 3 && statChildren.length <= 5;
                        })
                        .sort((left, right) => {
                          if (left.statChildren.length !== right.statChildren.length) {
                            return right.statChildren.length - left.statChildren.length;
                          }

                          return right.rect.bottom - left.rect.bottom;
                        })[0] || null;

                      if (fallbackContainer) {
                        const orderedChildren = fallbackContainer.statChildren.sort((left, right) => left.rect.left - right.rect.left);
                        const durationChild = [...orderedChildren].reverse().find(({ text }) => /^(?:\\d+:)?\\d{1,2}:\\d{2}$/.test(text));
                        orderedChildren
                          .filter(({ node }) => node !== orderedChildren[0]?.node && node !== durationChild?.node)
                          .forEach(({ node }) => {
                            node.setAttribute('data-focus-search-video-secondary-stat', 'true');
                          });
                        logSecondaryStatSample(
                          'fallbackContainer',
                          orderedChildren.map(({ text }) => text),
                          orderedChildren
                            .filter(({ node }) => node !== orderedChildren[0]?.node && node !== durationChild?.node)
                            .map(({ text }) => text)
                        );
                        return;
                      }

                      const resolveStatItemNode = (leafNode) => {
                        let currentNode = leafNode;

                        while (currentNode && currentNode !== coverShell) {
                          const parentNode = currentNode.parentElement;
                          if (!parentNode || parentNode === coverShell) {
                            return currentNode;
                          }

                          const siblings = Array.from(parentNode.children).filter((node) => isNodeVisible(node));
                          const siblingStatCount = siblings.filter((node) => {
                            const siblingText = normalizeLabel(node.textContent);
                            return !!siblingText && siblingText.length <= 16 && isStatLikeText(siblingText);
                          }).length;

                          if (siblings.length >= 2 && siblings.length <= 5 && siblingStatCount >= 2) {
                            return currentNode;
                          }

                          currentNode = parentNode;
                        }

                        return leafNode;
                      };

                      const overlayLeafNodes = Array.from(coverShell.querySelectorAll('span, div, a, li, p, strong, b'))
                        .filter((node) => isNodeVisible(node))
                        .map((node) => {
                          const normalizedText = normalizeLabel(node.textContent);
                          return {
                            node,
                            normalizedText
                          };
                        })
                        .filter(({ node, normalizedText }) => {
                          if (!normalizedText || normalizedText.length > 12) {
                            return false;
                          }

                          if (node.querySelector('img, picture, video, canvas')) {
                            return false;
                          }

                          if (Array.from(node.children).some((child) => normalizeLabel(child.textContent) === normalizedText)) {
                            return false;
                          }

                          const rect = node.getBoundingClientRect();
                          if (rect.width < 10 || rect.height < 10) {
                            return false;
                          }

                          const nearBottom = rect.bottom >= coverRect.bottom - Math.min(coverRect.height * 0.42, 48);
                          return nearBottom && isStatLikeText(normalizedText);
                        });

                      const itemMap = new Map();
                      overlayLeafNodes.forEach(({ node, normalizedText }) => {
                        const itemNode = resolveStatItemNode(node);
                        if (!itemNode) {
                          return;
                        }

                        const key = itemNode;
                        const rect = itemNode.getBoundingClientRect();
                        const existing = itemMap.get(key);
                        if (!existing || normalizedText.length > existing.normalizedText.length) {
                          itemMap.set(key, {
                            node: itemNode,
                            rect,
                            normalizedText
                          });
                        }
                      });

                      const overlayItems = Array.from(itemMap.values())
                        .sort((left, right) => {
                          const topOffset = left.rect.top - right.rect.top;
                          if (Math.abs(topOffset) > 2) {
                            return topOffset;
                          }

                          return left.rect.left - right.rect.left;
                        });

                      if (overlayItems.length < 3) {
                        return;
                      }

                      const durationCandidate = [...overlayItems].reverse().find(({ normalizedText }) => /^(?:\\d+:)?\\d{1,2}:\\d{2}$/.test(normalizedText));
                      const nonDurationStats = overlayItems.filter(({ node }) => node !== durationCandidate?.node);

                      nonDurationStats.slice(1).forEach(({ node }) => {
                        node.setAttribute('data-focus-search-video-secondary-stat', 'true');
                      });
                      logSecondaryStatSample(
                        'overlayItems',
                        overlayItems.map(({ normalizedText }) => normalizedText),
                        nonDurationStats.slice(1).map(({ normalizedText }) => normalizedText)
                      );
                    };

                    const collectVideoCells = (container) => {
                      const seenCells = new Set();
                      const result = [];
                      const clickableNodes = Array.from(container.querySelectorAll(searchVideoInteractiveSelector));

                      clickableNodes.forEach((node) => {
                        const canonicalURL = extractCanonicalVideoURL(node);
                        if (!canonicalURL || canonicalURL.indexOf('/video/') < 0) {
                          return;
                        }

                        const cell = findChildWithinContainer(container, node);
                        if (!cell || seenCells.has(cell)) {
                          return;
                        }

                        seenCells.add(cell);
                        result.push({
                          cell
                        });
                      });

                      return result;
                    };

                    const resolveVisibleCoverNode = (root) => {
                      const rawCoverNode = Array.from(root.querySelectorAll('img, picture, video, canvas')).find((node) => {
                        return isNodeVisible(node) || String(node.tagName || '').toLowerCase() === 'img';
                      }) || Array.from(root.querySelectorAll('[class*="cover"], [class*="image"], [class*="img"], [class*="pic"]')).find(isNodeVisible);

                      return rawCoverNode?.closest('[class*="cover"], [class*="image"], [class*="img"], [class*="pic"], figure, picture')
                        || rawCoverNode
                        || null;
                    };

                    const resolvePrimaryTitleNode = (root, coverShell) => {
                      return Array.from(root.querySelectorAll('[class*="title"], h3, h4, strong, a'))
                        .filter((node) => node !== root)
                        .filter((node) => node !== coverShell && !coverShell?.contains(node))
                        .filter((node) => !node.querySelector('img, picture, video, canvas'))
                        .filter((node) => {
                          const normalizedText = normalizeLabel(node.textContent);
                          return normalizedText.length >= 4 && normalizedText.length <= 80;
                        })
                        .sort((left, right) => {
                          const topOffset = left.getBoundingClientRect().top - right.getBoundingClientRect().top;
                          if (Math.abs(topOffset) > 1) {
                            return topOffset;
                          }

                          return normalizeLabel(left.textContent).length - normalizeLabel(right.textContent).length;
                        })[0] || null;
                    };

                    const markVideoLikeMetaNodes = (root, titleNode, coverShell, attributeName, limit = 2) => {
                      Array.from(root.querySelectorAll('[class*="desc"], [class*="info"], [class*="meta"], [class*="stats"], [class*="play"], [class*="view"], [class*="count"], [class*="duration"], .time, .up-name, .author, span, div'))
                        .filter((node) => node !== titleNode && node !== coverShell && !coverShell?.contains(node))
                        .filter((node) => {
                          const normalizedText = normalizeLabel(node.textContent);
                          if (!normalizedText || normalizedText.length > 40) {
                            return false;
                          }

                          return /播放|观看|弹幕|点赞|收藏|投币|分享|小时前|分钟前|昨天|:[0-5]\\d|万|亿|arcraiders/i.test(normalizedText);
                        })
                        .sort((left, right) => left.getBoundingClientRect().top - right.getBoundingClientRect().top)
                        .slice(0, limit)
                        .forEach((node) => {
                          node.setAttribute(attributeName, 'true');
                        });
                    };

                    const markVideoCell = (cell) => {
                      if (!cell) {
                        return;
                      }

                      cell.setAttribute('data-focus-search-video-card', 'true');

                      const coverNode = resolveVisibleCoverNode(cell);
                      const contentRoot = resolveSearchVideoContentRoot(cell, coverNode, null);
                      contentRoot?.setAttribute('data-focus-search-video-content-root', 'true');
                      const canonicalTargetURL = extractCanonicalVideoURL(contentRoot || cell);
                      if (canonicalTargetURL) {
                        cell.setAttribute('data-focus-search-video-target', canonicalTargetURL);
                        contentRoot?.setAttribute('data-focus-search-video-target', canonicalTargetURL);
                      }

                      let coverShell = null;
                      if (coverNode && contentRoot && contentRoot.contains(coverNode)) {
                        coverShell = findChildWithinContainer(contentRoot, coverNode) || coverNode;
                        coverShell.setAttribute('data-focus-search-video-cover', 'true');
                        markSecondaryCoverStats(coverShell);
                      }

                      const titleNode = resolvePrimaryTitleNode(contentRoot || cell, coverShell);

                      const titleShell = titleNode && contentRoot && contentRoot.contains(titleNode)
                        ? (findChildWithinContainer(contentRoot, titleNode) || titleNode)
                        : null;
                      if (titleShell && titleShell !== coverShell && titleShell !== titleNode) {
                        titleShell.setAttribute('data-focus-search-video-info-shell', 'true');
                      }
                      if (titleNode) {
                        titleNode.setAttribute('data-focus-search-video-title', 'true');
                      }

                      markVideoLikeMetaNodes(contentRoot || cell, titleNode, coverShell, 'data-focus-search-video-meta', 2);

                      if (canonicalTargetURL) {
                        const debugIndex = incrementDebugCounter('searchVideoCardMarkCount');
                        if (debugIndex <= 8) {
                          debugSearch('searchVideoCardMarked', {
                            index: debugIndex,
                            targetURL: canonicalTargetURL,
                            title: normalizeLabel(titleNode?.textContent || '').slice(0, 80),
                            hasCover: !!coverShell,
                            contentRootTag: contentRoot?.tagName || null,
                            cellClass: String(cell.className || '').slice(0, 160)
                          });
                        }
                      } else {
                        const missingTargetIndex = incrementDebugCounter('searchVideoMissingTargetCount');
                        if (missingTargetIndex <= 4) {
                          debugSearch('searchVideoCardMissingTarget', {
                            index: missingTargetIndex,
                            cellClass: String(cell.className || '').slice(0, 160),
                            cellText: normalizeLabel(cell.textContent || '').slice(0, 80)
                          });
                        }
                      }
                    };

                    const findSearchProfilePreviewContainer = (item) => {
                      const itemRect = item.getBoundingClientRect();
                      return Array.from(item.querySelectorAll('div, section, ul, ol'))
                        .map((node) => {
                          const strictVideoCells = collectVideoCells(node).filter(({ cell }) => {
                            return !!cell.querySelector('img, picture, video, canvas');
                          });
                          const fallbackCells = Array.from(node.children || [])
                            .filter((child) => child && child.nodeType === 1)
                            .filter((child) => child.querySelector('img, picture, video, canvas'))
                            .filter((child) => child.querySelector(searchVideoInteractiveSelector));
                          const cells = strictVideoCells.length >= 2
                            ? strictVideoCells.map(({ cell }) => ({ cell }))
                            : fallbackCells.map((cell) => ({ cell }));
                          return {
                            node,
                            videoCells: cells,
                            strictVideoCellCount: strictVideoCells.length,
                            rect: node.getBoundingClientRect(),
                            depth: node.querySelectorAll('*').length,
                            childCount: node.children.length
                          };
                        })
                        .filter(({ node, videoCells, rect, childCount }) => {
                          if (videoCells.length < 2) {
                            return false;
                          }

                          if (!node.parentElement || !item.contains(node)) {
                            return false;
                          }

                          const widthMatches = itemRect.width < 40 || rect.width < 40 || rect.width >= Math.min(itemRect.width * 0.52, 180);
                          const heightMatches = rect.height >= 72 || !!node.querySelector('img, picture, video, canvas');
                          const topMatches = itemRect.top === 0 || rect.top >= itemRect.top - 4;

                          return widthMatches && heightMatches && topMatches && childCount >= 2;
                        })
                        .sort((left, right) => {
                          if (left.strictVideoCellCount !== right.strictVideoCellCount) {
                            return right.strictVideoCellCount - left.strictVideoCellCount;
                          }
                          if (left.videoCells.length !== right.videoCells.length) {
                            return right.videoCells.length - left.videoCells.length;
                          }
                          if (left.depth !== right.depth) {
                            return left.depth - right.depth;
                          }
                          return left.rect.top - right.rect.top;
                        })[0] || null;
                    };

                    const markSearchProfileVideoCell = (cell) => {
                      if (!cell) {
                        return;
                      }

                      cell.setAttribute('data-focus-search-up-video', 'true');

                      const coverNode = resolveVisibleCoverNode(cell);
                      const contentRoot = resolveSearchVideoContentRoot(cell, coverNode, null);
                      const canonicalTargetURL = extractCanonicalVideoURL(contentRoot || cell);
                      if (canonicalTargetURL) {
                        cell.setAttribute('data-focus-search-video-target', canonicalTargetURL);
                        contentRoot?.setAttribute('data-focus-search-video-target', canonicalTargetURL);
                        contentRoot?.setAttribute('data-focus-search-up-video-target', 'true');
                      }

                      let coverShell = null;
                      if (coverNode && contentRoot && contentRoot.contains(coverNode)) {
                        coverShell = findChildWithinContainer(contentRoot, coverNode) || coverNode;
                        coverShell.setAttribute('data-focus-search-up-video-cover', 'true');
                        markSecondaryCoverStats(coverShell);
                      }

                      const titleNode = resolvePrimaryTitleNode(contentRoot || cell, coverShell);
                      if (titleNode) {
                        titleNode.setAttribute('data-focus-search-up-video-title', 'true');
                      }

                      markVideoLikeMetaNodes(contentRoot || cell, titleNode, coverShell, 'data-focus-search-up-video-meta', 1);
                    };

                    const applySearchProfileCards = () => {
                      Array.from(document.querySelectorAll('.up-list .up-item, .user-list .user-item')).forEach((item) => {
                        item.setAttribute('data-focus-search-up-card', 'true');
                        const preview = findSearchProfilePreviewContainer(item);
                        if (!preview) {
                          return;
                        }

                        preview.node.setAttribute('data-focus-search-up-strip', 'true');
                        preview.videoCells.forEach(({ cell }) => {
                          markSearchProfileVideoCell(cell);
                        });
                      });
                    };

                    const applySearchVideoGrid = () => {
                      clearSearchVideoMarkers();
                      installSearchVideoNavigationInterceptor();

                      const explicitContainers = Array.from(document.querySelectorAll('.video-list')).filter(isRenderableContainer);
                      const fallbackContainers = explicitContainers.length > 0
                        ? explicitContainers
                        : Array.from(document.querySelectorAll('.search-list, .search-all-list, .result-wrap, .left-wrap, main')).filter(isRenderableContainer);
                      let gridContainerCount = 0;
                      let markedCellCount = 0;

                      fallbackContainers.forEach((container) => {
                        const videoCells = collectVideoCells(container);
                        if (videoCells.length < 2) {
                          return;
                        }

                        gridContainerCount += 1;
                        container.setAttribute('data-focus-search-video-grid', 'true');
                        videoCells.forEach(({ cell }) => {
                          cell.setAttribute('data-focus-search-video-cell', 'true');
                          markedCellCount += 1;
                          markVideoCell(cell);
                        });
                      });

                      applySearchProfileCards();

                      const gridSummarySignature = [
                        explicitContainers.length,
                        fallbackContainers.length,
                        gridContainerCount,
                        markedCellCount
                      ].join(':');
                      if (state.searchVideoGridSummary !== gridSummarySignature) {
                        state.searchVideoGridSummary = gridSummarySignature;
                        debugSearch('searchVideoGridApplied', {
                          explicitContainerCount: explicitContainers.length,
                          fallbackContainerCount: fallbackContainers.length,
                          gridContainerCount,
                          markedCellCount
                        });
                      }
                    };

                    const findSearchFilterRoot = () => {
                      if (state.searchFilterSourceRoot?.isConnected) {
                        return state.searchFilterSourceRoot;
                      }

                      const directRoot = document.querySelector('.search-conditions');
                      if (directRoot && isNodeVisible(directRoot)) {
                        state.searchFilterSourceRoot = directRoot;
                        return directRoot;
                      }

                      const candidates = Array.from(document.querySelectorAll('div, section, ul, article'))
                        .map((node) => {
                          const text = normalizeLabel(node.textContent);
                          const rect = node.getBoundingClientRect();
                          const matchCount = searchFilterKeywords.filter((keyword) => text.includes(normalizeLabel(keyword))).length;
                          const interactives = node.querySelectorAll(interactiveSelector).length;
                          return {
                            node,
                            textLength: text.length,
                            matchCount,
                            interactives,
                            top: rect.top
                          };
                        })
                        .filter((candidate) => candidate.matchCount >= 3
                          && candidate.interactives >= 3
                          && candidate.textLength <= 220
                          && candidate.top < Math.max(window.innerHeight * 0.65, 480))
                        .sort((left, right) => {
                          if (left.matchCount !== right.matchCount) {
                            return right.matchCount - left.matchCount;
                          }
                          if (left.textLength !== right.textLength) {
                            return left.textLength - right.textLength;
                          }
                          if (left.interactives !== right.interactives) {
                            return left.interactives - right.interactives;
                          }
                          return left.top - right.top;
                        });

                      const root = candidates[0]?.node || null;
                      if (root) {
                        state.searchFilterSourceRoot = root;
                      }
                      return root;
                    };

                    const findSearchTypeNavRoot = () => {
                      if (state.searchTypeNavRoot?.isConnected) {
                        return state.searchTypeNavRoot;
                      }

                      const directRoot = document.querySelector('.search-tabs, .vui_tabs--navbar, .vui_tabs--nav');
                      if (directRoot && isNodeVisible(directRoot)) {
                        state.searchTypeNavRoot = directRoot.closest('.search-tabs') || directRoot;
                        return state.searchTypeNavRoot;
                      }

                      const directChildMatchCount = (node) => {
                        const children = Array.from(node.children || []);
                        const labels = children
                          .map((child) => normalizeLabel(child.textContent))
                          .filter(Boolean);

                        if (labels.length < 3 || labels.length > 8) {
                          return 0;
                        }

                        return searchTypeLabels.filter((label) => labels.some((value) => value.includes(normalizeLabel(label)))).length;
                      };

                      const candidates = Array.from(document.querySelectorAll('nav, div, ul, section'))
                        .filter((node) => !node.hasAttribute?.('data-focus-search-filter-shell')
                          && !node.querySelector?.('[data-focus-search-filter-shell]'))
                        .map((node) => {
                          const text = normalizeLabel(node.textContent);
                          const rect = node.getBoundingClientRect();
                          const matchCount = searchTypeLabels.filter((label) => text.includes(normalizeLabel(label))).length;
                          const directMatchCount = directChildMatchCount(node);
                          const containsFilterKeyword = searchFilterKeywords.some((keyword) => text.includes(normalizeLabel(keyword)));
                          const containsSearchInput = !!node.querySelector('input, textarea');
                          const interactives = node.querySelectorAll('a, button, [role="tab"], [role="button"]').length;
                          return {
                            node,
                            textLength: text.length,
                            matchCount,
                            directMatchCount,
                            containsFilterKeyword,
                            containsSearchInput,
                            interactives,
                            height: rect.height,
                            top: rect.top
                          };
                        })
                        .filter((candidate) => (candidate.directMatchCount >= 3 || candidate.matchCount >= 4)
                          && !candidate.containsFilterKeyword
                          && !candidate.containsSearchInput
                          && candidate.interactives >= 3
                          && candidate.textLength <= 220
                          && candidate.height <= 100
                          && candidate.top < Math.max(window.innerHeight * 0.58, 360))
                        .sort((left, right) => {
                          if (left.directMatchCount !== right.directMatchCount) {
                            return right.directMatchCount - left.directMatchCount;
                          }
                          if (left.top !== right.top) {
                            return left.top - right.top;
                          }
                          if (left.matchCount !== right.matchCount) {
                            return right.matchCount - left.matchCount;
                          }
                          return left.textLength - right.textLength;
                        });

                      const root = candidates[0]?.node || null;
                      if (root) {
                        state.searchTypeNavRoot = root;
                      }
                      return root;
                    };

                    const hideSearchTypeNav = () => {
                      const root = findSearchTypeNavRoot();
                      if (!root) {
                        return;
                      }

                      root.setAttribute('data-focus-search-type-root', 'true');
                      root.querySelectorAll('.vui_tabs, .vui_tabs--navbar, .vui_tabs--nav').forEach((node) => {
                        node.style.setProperty('display', 'none', 'important');
                      });
                      root.style.setProperty('display', 'none', 'important');
                      root.style.setProperty('height', '0', 'important');
                      root.style.setProperty('max-height', '0', 'important');
                      root.style.setProperty('min-height', '0', 'important');
                      root.style.setProperty('margin', '0', 'important');
                      root.style.setProperty('padding', '0', 'important');
                      root.style.setProperty('overflow', 'hidden', 'important');
                    };

                    const isFilterNodeActive = (node) => {
                      if (!node) {
                        return false;
                      }

                      const activeSelector = '.active, .is-active, .on, .selected, .current, [aria-selected="true"], [aria-checked="true"], [aria-pressed="true"], [data-state="active"]';
                      return node.matches?.(activeSelector)
                        || !!node.querySelector?.(activeSelector)
                        || String(node.getAttribute?.('class') || '').toLowerCase().includes('active');
                    };

                    const resolveActionNode = (node) => {
                      if (!node) {
                        return null;
                      }

                      let currentNode = node;
                      while (currentNode && currentNode !== document.body) {
                        if (currentNode.matches?.(interactiveSelector) || typeof currentNode.onclick === 'function' || currentNode.tabIndex >= 0) {
                          return currentNode;
                        }
                        currentNode = currentNode.parentElement;
                      }

                      return node.querySelector?.(interactiveSelector) || node;
                    };

                    const findFilterControl = (root, label) => {
                      const normalizedLabel = normalizeLabel(label);
                      const matches = Array.from(root.querySelectorAll('*'))
                        .map((node) => {
                          const text = normalizeLabel(node.textContent);
                          if (!text || !text.includes(normalizedLabel) || text.length > normalizedLabel.length + 10) {
                            return null;
                          }

                          return {
                            node,
                            textLength: text.length,
                            depth: String(node.tagName || '').length + node.querySelectorAll('*').length
                          };
                        })
                        .filter(Boolean)
                        .sort((left, right) => {
                          if (left.textLength !== right.textLength) {
                            return left.textLength - right.textLength;
                          }
                          return left.depth - right.depth;
                        });

                      const bestMatch = matches.find((candidate) => !matches.some((other) => other !== candidate && candidate.node.contains(other.node)));
                      return resolveActionNode(bestMatch?.node || matches[0]?.node || null);
                    };

                    const resolveFilterControl = (root, label) => {
                      state.searchFilterControlCache = state.searchFilterControlCache || {};
                      const cachedControl = state.searchFilterControlCache[label];
                      if (cachedControl?.isConnected) {
                        return cachedControl;
                      }

                      const liveControl = findFilterControl(root, label);
                      if (liveControl) {
                        state.searchFilterControlCache[label] = liveControl;
                      }
                      return liveControl;
                    };

                    const dispatchFilterControl = (node) => {
                      if (!node) {
                        return;
                      }

                      if (node.matches?.('input, textarea, select')) {
                        node.focus?.();
                        node.click?.();
                        node.dispatchEvent(new Event('change', { bubbles: true }));
                        return;
                      }

                      const eventNames = ['pointerdown', 'mousedown', 'pointerup', 'mouseup'];
                      eventNames.forEach((eventName) => {
                        const EventConstructor = eventName.startsWith('pointer') && typeof PointerEvent === 'function'
                          ? PointerEvent
                          : MouseEvent;
                        node.dispatchEvent(new EventConstructor(eventName, {
                          bubbles: true,
                          cancelable: true,
                          view: window
                        }));
                      });

                      if (typeof node.click === 'function') {
                        node.click();
                      }

                      node.dispatchEvent(new MouseEvent('click', {
                        bubbles: true,
                        cancelable: true,
                        view: window
                      }));
                      node.focus?.();
                    };

                    const setOriginalFilterBoardCollapsed = (root, collapsed) => {
                      if (!root) {
                        return;
                      }

                      if (!collapsed) {
                        ['position', 'left', 'top', 'width', 'height', 'overflow', 'opacity', 'pointer-events', 'margin', 'padding'].forEach((propertyName) => {
                          root.style.removeProperty(propertyName);
                        });
                        return;
                      }

                      root.style.setProperty('position', 'absolute', 'important');
                      root.style.setProperty('left', '-9999px', 'important');
                      root.style.setProperty('top', '0', 'important');
                      root.style.setProperty('width', '1px', 'important');
                      root.style.setProperty('height', '1px', 'important');
                      root.style.setProperty('overflow', 'hidden', 'important');
                      root.style.setProperty('opacity', '0', 'important');
                      root.style.setProperty('pointer-events', 'none', 'important');
                      root.style.setProperty('margin', '0', 'important');
                      root.style.setProperty('padding', '0', 'important');
                    };

                    const removeMirroredFilterBoard = () => {
                      document.querySelector('[data-focus-search-filter-shell]')?.remove();
                      if (state.searchFilterSourceRoot?.isConnected) {
                        setOriginalFilterBoardCollapsed(state.searchFilterSourceRoot, false);
                      }
                      state.searchFilterControlCache = {};
                    };

                    const scheduleSearchFilterRefresh = () => {
                      clearTimeout(state.searchFilterRefreshTimer);
                      state.searchFilterRefreshTimer = setTimeout(() => {
                        rewriteAll();
                        decorateSearchInput();
                        applySearchVideoGrid();
                        hidePromotedSearchBlocks();
                        hideSearchTypeNav();
                        mirrorSearchFilterBoard();
                      }, 18);
                      clearTimeout(state.searchFilterRefreshTimerLate);
                      state.searchFilterRefreshTimerLate = setTimeout(() => {
                        rewriteAll();
                        decorateSearchInput();
                        applySearchVideoGrid();
                        hidePromotedSearchBlocks();
                        hideSearchTypeNav();
                        mirrorSearchFilterBoard();
                      }, 96);
                    };

                    const triggerFilterSelection = (label) => {
                      const root = findSearchFilterRoot();
                      if (!root) {
                        return false;
                      }

                      const moreFilterControl = resolveFilterControl(root, '更多筛选');
                      const requiresExpandedPanel = dateFilterLabels.includes(label) || durationFilterLabels.includes(label);
                      if (requiresExpandedPanel && !state.searchFilterExpanded) {
                        state.searchFilterExpanded = true;
                        dispatchFilterControl(moreFilterControl);
                      }

                      const liveControl = resolveFilterControl(root, label);
                      if (!liveControl) {
                        return false;
                      }

                      dispatchFilterControl(liveControl);
                      scheduleSearchFilterRefresh();
                      return true;
                    };

                    const mirrorSearchFilterBoard = () => {
                      const root = findSearchFilterRoot();
                      if (!root) {
                        removeMirroredFilterBoard();
                        return;
                      }

                      const expanded = !!state.searchFilterExpanded;
                      const toFilterItem = (label) => ({
                        label,
                        control: resolveFilterControl(root, label)
                      });
                      const compactPrimaryItems = collapsedPrimaryLabels
                        .map(toFilterItem)
                        .filter((item) => item.control);
                      const extendedPrimaryItems = expanded
                        ? extendedPrimaryLabels
                            .map(toFilterItem)
                            .filter((item) => item.control)
                        : [];
                      const secondaryRows = expanded
                        ? [dateFilterLabels, durationFilterLabels].map((labels) => labels
                            .map(toFilterItem)
                            .filter((item) => item.control))
                        : [];
                      const hasHiddenActiveFilter = extendedPrimaryLabels.some((label) => isFilterNodeActive(resolveFilterControl(root, label)))
                        || dateFilterLabels.some((label) => isFilterNodeActive(resolveFilterControl(root, label)))
                        || durationFilterLabels.some((label) => isFilterNodeActive(resolveFilterControl(root, label)));
                      const moreFilterControl = resolveFilterControl(root, '更多筛选');
                      const rows = [
                        {
                          kind: 'primary',
                          items: compactPrimaryItems.concat([
                            {
                              label: '更多筛选',
                              control: moreFilterControl,
                              isToggle: true,
                              isActive: expanded || hasHiddenActiveFilter
                            }
                          ])
                        }
                      ];

                      if (expanded && extendedPrimaryItems.length > 0) {
                        rows.push({
                          kind: 'secondary',
                          items: extendedPrimaryItems
                        });
                      }

                      secondaryRows.forEach((items) => {
                        if (items.length > 0) {
                          rows.push({
                            kind: 'secondary',
                            items
                          });
                        }
                      });

                      const chipCount = rows.reduce((count, row) => count + row.items.length, 0);
                      if (chipCount < 3) {
                        removeMirroredFilterBoard();
                        return;
                      }

                      let shell = document.querySelector('[data-focus-search-filter-shell]');
                      if (!shell) {
                        shell = document.createElement('section');
                        shell.setAttribute('data-focus-search-filter-shell', 'true');
                      }

                      shell.replaceChildren();
                      rows.forEach(({ kind, items }) => {
                        if (items.length === 0) {
                          return;
                        }

                        const row = document.createElement('div');
                        row.setAttribute('data-focus-search-filter-row', 'true');
                        row.setAttribute('data-focus-row-kind', kind);

                        items.forEach(({ label, control, isToggle = false, isActive = false }) => {
                          const chip = document.createElement('button');
                          chip.type = 'button';
                          chip.textContent = label;
                          chip.setAttribute('data-focus-search-filter-chip', 'true');
                          chip.setAttribute('data-focus-active', isToggle
                            ? (isActive ? 'true' : 'false')
                            : (isFilterNodeActive(control) ? 'true' : 'false'));
                          chip.addEventListener('click', (event) => {
                            event.preventDefault();
                            event.stopPropagation();

                            if (isToggle) {
                              const nextExpanded = !expanded;
                              state.searchFilterExpanded = nextExpanded;
                              if (nextExpanded && control && (!resolveFilterControl(root, '全部日期') || !resolveFilterControl(root, '全部时长'))) {
                                dispatchFilterControl(control);
                              }
                              mirrorSearchFilterBoard();
                              scheduleSearchFilterRefresh();
                              return;
                            }

                            triggerFilterSelection(label);
                          });
                          row.appendChild(chip);
                        });

                        shell.appendChild(row);
                      });

                      if (root.parentNode && shell.parentNode !== root.parentNode) {
                        root.parentNode.insertBefore(shell, root);
                      } else if (root.parentNode) {
                        root.parentNode.insertBefore(shell, root);
                      }

                      root.setAttribute('data-focus-search-filter-root', 'true');
                      setOriginalFilterBoardCollapsed(root, true);
                    };

                    rewriteAll();
                    decorateSearchInput();
                    applySearchVideoGrid();
                    hidePromotedSearchBlocks();
                    hideSearchTypeNav();
                    mirrorSearchFilterBoard();

                    if (!state.openWrapped) {
                      state.openWrapped = true;
                      const originalOpen = window.open?.bind(window);
                      if (originalOpen) {
                        window.open = function(url) {
                          const args = Array.from(arguments);
                          if (typeof url === 'string') {
                            args[0] = extractCanonicalFromRawValue(url) || helpers.canonicalizeBilibiliURL(url);
                          }
                          return originalOpen.apply(this, args);
                        };
                      }
                    }

                    const installNavigationInterceptor = (eventName) => {
                      document.addEventListener(eventName, (event) => {
                        const target = event.target;
                        if (!target || !target.closest) {
                          return;
                        }

                        if (event.type === 'keydown' && event.key !== 'Enter' && event.key !== ' ') {
                          return;
                        }

                        if (event.type === 'click' && wasRecentScrollGesture()) {
                          return;
                        }

                        const eventPath = typeof event.composedPath === 'function' ? event.composedPath() : [];
                        for (const item of eventPath) {
                          const canonicalURL = extractCanonicalVideoURL(item);
                          if (!canonicalURL) {
                            continue;
                          }

                          debugSearch('searchNavigationIntercept', {
                            eventName,
                            source: 'eventPath',
                            canonicalURL,
                            nodeTag: item?.tagName || null,
                            nodeClass: String(item?.className || '').slice(0, 160),
                            pageURL: location.href
                          });

                          event.preventDefault();
                          event.stopPropagation();
                          event.stopImmediatePropagation?.();
                          window.location.assign(canonicalURL);
                          return;
                        }

                        const anchor = target.closest('a[href]');
                        if (anchor) {
                          const canonicalURL = extractCanonicalVideoURL(anchor);
                          if (canonicalURL) {
                            debugSearch('searchNavigationIntercept', {
                              eventName,
                              source: 'anchor',
                              canonicalURL,
                              anchorHref: anchor.href,
                              anchorClass: String(anchor.className || '').slice(0, 160),
                              pageURL: location.href
                            });
                            event.preventDefault();
                            event.stopPropagation();
                            event.stopImmediatePropagation?.();
                            if (anchor.href !== canonicalURL) {
                              anchor.href = canonicalURL;
                            }
                            window.location.assign(canonicalURL);
                          }
                          return;
                        }

                        const datasetNode = target.closest('[data-href], [data-url], [data-link], [data-target-url], [data-jump-url], [data-report-click], [data-arcurl], [data-target]');
                        if (!datasetNode) {
                          return;
                        }

                        const canonicalURL = candidateKeys
                          .map((key) => rewriteDatasetURL(datasetNode, key))
                          .find(Boolean);
                        if (!canonicalURL) {
                          return;
                        }

                        debugSearch('searchNavigationIntercept', {
                          eventName,
                          source: 'dataset',
                          canonicalURL,
                          datasetClass: String(datasetNode.className || '').slice(0, 160),
                          pageURL: location.href
                        });

                        event.preventDefault();
                        event.stopPropagation();
                        event.stopImmediatePropagation?.();
                        window.location.assign(canonicalURL);
                      }, true);
                    };

                    if (!state.clickInstalled) {
                      state.clickInstalled = true;
                      installSearchScrollGuard();
                      installNavigationInterceptor('click');
                      installNavigationInterceptor('keydown');
                    }

                    if (!state.searchObserverInstalled) {
                      state.searchObserverInstalled = true;
                      const observer = new MutationObserver((mutations) => {
                        const shouldRefresh = mutations.some((mutation) => {
                          if (mutation.type === 'childList' && (mutation.addedNodes.length || mutation.removedNodes.length)) {
                            return true;
                          }
                          if (mutation.type === 'attributes') {
                            return true;
                          }
                          return false;
                        });

                        if (shouldRefresh) {
                          scheduleSearchFilterRefresh();
                        }
                      });

                      observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ['class', 'style', 'href', 'data-href', 'data-url']
                      });
                    }
                    """,
                    settingKey: .searchMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "opus-prune",
            hosts: ["bilibili.com", "www.bilibili.com", "m.bilibili.com"],
            pathPrefixes: ["/opus/"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "opus-mask",
                    requiredSelectors: [".bili-opus-view", ".opus-module-content"],
                    optionalSelectors: ["#bili-header-container", ".bili-header", ".international-header"],
                    action: .prune,
                    css: """
                    #biliMainHeader,
                    #bili-header-container,
                    .bili-header,
                    .international-header,
                    .fixed-header,
                    .opus-aside,
                    .aside-container,
                    .side-toolbar,
                    .recommend-container,
                    .open-app-btn,
                    .m-bottom-app-download,
                    [class*="openapp"],
                    [class*="download"] {
                      display: none !important;
                    }
                    """,
                    settingKey: .dynamicMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "opus-repair",
            hosts: ["bilibili.com", "www.bilibili.com", "m.bilibili.com"],
            pathPrefixes: ["/opus/"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "opus-layout",
                    requiredSelectors: [".bili-opus-view", ".opus-module-content"],
                    optionalSelectors: [".opus-detail", ".opus-module-author", ".opus-module-top"],
                    action: .repair,
                    css: """
                    html,
                    body,
                    #app,
                    main,
                    .bili-opus-view,
                    .opus-detail,
                    .opus-detail__primary,
                    .opus-module-top,
                    .opus-module-author,
                    .opus-module-title,
                    .opus-module-content,
                    .opus-module-collection,
                    .opus-module-album,
                    .opus-module-album__item {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      box-sizing: border-box !important;
                    }

                    html,
                    body,
                    #app,
                    main,
                    .bili-opus-view,
                    .opus-detail {
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                      background: #f5f7fb !important;
                    }

                    body {
                      padding-bottom: 136px !important;
                    }

                    main,
                    .bili-opus-view,
                    .opus-detail {
                      display: block !important;
                    }

                    main,
                    .bili-opus-view,
                    .opus-detail {
                      padding: 12px !important;
                    }

                    .opus-detail__primary,
                    .opus-module-top,
                    .opus-module-author,
                    .opus-module-content,
                    .opus-module-collection {
                      background: #ffffff !important;
                      border-radius: 20px !important;
                      box-shadow: 0 12px 28px rgba(15, 23, 42, 0.06) !important;
                    }

                    .opus-module-top,
                    .opus-module-author,
                    .opus-module-content,
                    .opus-module-collection {
                      padding: 16px !important;
                    }

                    .opus-detail__primary,
                    .opus-module-content,
                    .opus-module-album__item {
                      display: block !important;
                      grid-template-columns: 1fr !important;
                    }

                    .opus-module-album,
                    .opus-module-collection {
                      display: grid !important;
                      grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                      gap: 10px !important;
                    }

                    .opus-module-album__item,
                    .opus-module-collection > * {
                      aspect-ratio: 1 / 1 !important;
                      overflow: hidden !important;
                      border-radius: 16px !important;
                    }

                    .opus-module-album__item:only-child,
                    .opus-module-collection > *:only-child {
                      grid-column: 1 / -1 !important;
                      aspect-ratio: auto !important;
                    }

                    .opus-module-content *,
                    .opus-module-album *,
                    .opus-module-collection * {
                      max-width: 100% !important;
                      min-width: 0 !important;
                      box-sizing: border-box !important;
                    }

                    .opus-module-content img,
                    .opus-module-content video,
                    .opus-module-album img,
                    .opus-module-album video,
                    .opus-module-content canvas {
                      width: 100% !important;
                      max-width: 100% !important;
                      height: auto !important;
                      display: block !important;
                      margin: 0 auto !important;
                      border-radius: 16px !important;
                      object-fit: cover !important;
                    }

                    .opus-module-content,
                    .opus-module-top,
                    .opus-module-author {
                      word-break: break-word !important;
                    }
                    """,
                    script: """
                    const state = helpers.featureState;

                    const revealLazyMedia = (root) => {
                      if (!root || !root.querySelectorAll) {
                        return;
                      }

                      root.querySelectorAll('img, source').forEach((node) => {
                        const src = node.getAttribute('data-src') || node.getAttribute('data-url') || node.getAttribute('data-original');
                        const srcset = node.getAttribute('data-srcset') || node.getAttribute('data-set');

                        if (src && !node.getAttribute('src')) {
                          node.setAttribute('src', src);
                        }

                        if (srcset && !node.getAttribute('srcset')) {
                          node.setAttribute('srcset', srcset);
                        }

                        node.setAttribute('loading', 'eager');
                        node.setAttribute('decoding', 'async');
                      });
                    };

                    revealLazyMedia(document);

                    if (!state.lazyMediaObserverInstalled) {
                      state.lazyMediaObserverInstalled = true;
                      const observer = new MutationObserver((mutations) => {
                        mutations.forEach((mutation) => {
                          mutation.addedNodes.forEach((node) => revealLazyMedia(node));
                        });
                      });

                      observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true
                      });
                    }
                    """,
                    settingKey: .dynamicMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "live-prune",
            hosts: ["live.bilibili.com"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "live-mask",
                    action: .prune,
                    css: """
                    #link-footer-vm,
                    .link-footer-ctnr,
                    .right-ctnr,
                    .right-area,
                    .link-navbar-ctnr,
                    .search-block,
                    .shortcuts-ctnr,
                    .room-bg-ctnr,
                    .z-room-background,
                    .aside-area,
                    #aside-area-vm,
                    .rank-list-ctnr,
                    .gift-control-panel,
                    .gift-panel,
                    .chat-control-panel,
                    .chat-history-list,
                    .chat-history-panel,
                    #chat-control-panel-vm,
                    #chat-history-list-vm,
                    .hot-rank-wrap,
                    .room-popular-rank,
                    .activity-banner-ctnr,
                    .guard-ent,
                    .user-panel-ctnr,
                    .sidebar-btn,
                    .slot-ctnr,
                    .recommend-area,
                    .recommend-card,
                    .link-popup-ctnr,
                    .lite-pay-ctnr,
                    .recharge-stores-ctnr,
                    .user-title-using-cntr,
                    .user-title-sending-cntr,
                    [class*="chat-history"],
                    [class*="aside-area"],
                    [class*="gift-panel"],
                    [class*="right-ctnr"],
                    [class*="rank-list"],
                    [class*="footer-ctnr"] {
                      display: none !important;
                    }
                    """,
                    settingKey: .playerMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "live-repair",
            hosts: ["live.bilibili.com"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "live-layout",
                    action: .repair,
                    css: """
                    html,
                    body,
                    #app,
                    #live-app,
                    main,
                    .app-content,
                    .live-room-app,
                    .app-body,
                    .room-page,
                    .player-and-aside-area,
                    .player-ctnr,
                    .left-container,
                    #player-ctnr,
                    #live-player {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                      box-sizing: border-box !important;
                      background: #ffffff !important;
                    }

                    body {
                      padding-bottom: 148px !important;
                    }

                    .top-nav-ctnr,
                    .top-nav,
                    .web-player-nav,
                    .room-header-ctnr,
                    .head-info-ctnr,
                    .left-entry,
                    .right-entry,
                    #right-part,
                    .user-info {
                      display: none !important;
                    }

                    .room-player-wrap,
                    .live-room-app,
                    .live-room-wrapper,
                    .room-ctnr,
                    .left-ctnr,
                    .left-container,
                    .player-and-aside-area,
                    .player-ctnr,
                    .web-player-controller-wrap,
                    #live-player {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                    }

                    .room-player-wrap,
                    .room-ctnr,
                    .live-room-wrapper,
                    .player-and-aside-area,
                    .player-ctnr {
                      display: block !important;
                    }

                    .left-ctnr,
                    .left-container {
                      flex: 1 1 auto !important;
                    }

                    .player-ctnr,
                    #live-player,
                    video {
                      border-radius: 0 !important;
                    }

                    .player-and-aside-area,
                    .player-ctnr,
                    #player-ctnr {
                      height: auto !important;
                    }

                    .room-info-ctnr,
                    .room-info-down-row,
                    .room-info-up-row,
                    .live-skin-normal-a-text,
                    .upper-row,
                    .lower-row {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      box-sizing: border-box !important;
                    }

                    .room-info-ctnr,
                    .room-info-up-row,
                    .room-info-down-row {
                      padding-left: 12px !important;
                      padding-right: 12px !important;
                    }

                    .head-info-section,
                    .header-info-ctnr,
                    #head-info-vm {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 12px 14px !important;
                      box-sizing: border-box !important;
                      border-radius: 0 !important;
                    }
                    """,
                    settingKey: .playerMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "video-prune",
            hosts: ["bilibili.com", "m.bilibili.com", "www.bilibili.com"],
            pathPrefixes: ["/video/", "/bangumi/play/", "/blackboard/html5player.html", "/blackboard/html5mobileplayer.html"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "player-mask",
                    requiredSelectors: [".m-video-related", ".player-container", ".video-container"],
                    optionalSelectors: [".launch-app-btn", ".recom-list", ".m-nav-bottom"],
                    action: .prune,
                    css: """
                    .m-video-related,
                    .m-video2-recom,
                    .m-video-related-wrap,
                    .recom-wrapper,
                    .recom-list,
                    .card-box,
                    .launch-app-btn,
                    .open-app-btn,
                    .openapp-btn,
                    .download-btn,
                    .download-layer,
                    .m-video-open-app,
                    .video-open-app,
                    .video-guide-open-app,
                    .m-video-float-openapp,
                    .m-bottom-app-download,
                    .m-video-up-app,
                    .m-nav-bottom,
                    .v-card-module,
                    .download-entry,
                    .download-client-trigger,
                    #commentapp,
                    [class*="openapp"],
                    [id*="openapp"] {
                      display: none !important;
                    }
                    """,
                    settingKey: .playerMaskEnabled
                ),
            ]
        ),
        FocusPageRule(
            id: "video-repair",
            hosts: ["bilibili.com", "m.bilibili.com", "www.bilibili.com"],
            pathPrefixes: ["/video/", "/bangumi/play/", "/blackboard/html5player.html", "/blackboard/html5mobileplayer.html"],
            runPhase: .documentEnd,
            features: [
                FocusFeature(
                    featureId: "player-layout",
                    requiredSelectors: ["#playerWrap"],
                    optionalSelectors: [".video-pod", ".left-container", ".right-container"],
                    action: .repair,
                    css: """
                    html,
                    body,
                    #app,
                    main,
                    #mirror-vdcon,
                    .video-container,
                    .video-container-v1 {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100vw !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      overflow-x: hidden !important;
                      box-sizing: border-box !important;
                    }

                    body {
                      padding-bottom: 164px !important;
                      background: #0f1115 !important;
                    }

                    html[data-focus-theme='light'] body {
                      background: #ffffff !important;
                    }

                    html[data-focus-theme='dark'],
                    html[data-focus-theme='dark'] body,
                    html[data-focus-theme='dark'] #app,
                    html[data-focus-theme='dark'] main,
                    html[data-focus-theme='dark'] #mirror-vdcon,
                    html[data-focus-theme='dark'] .video-container,
                    html[data-focus-theme='dark'] .video-container-v1,
                    html[data-focus-theme='dark'] .left-container,
                    html[data-focus-theme='dark'] .right-container,
                    html[data-focus-theme='dark'] .right-container-inner {
                      background: #0f1115 !important;
                    }

                    #biliMainHeader,
                    #bili-header-container,
                    .bili-header,
                    .international-header,
                    .fixed-header,
                    #viewbox_report,
                    .video-info-container,
                    #v_desc,
                    .video-desc-container,
                    .video-tag-container,
                    .left-banner,
                    #commentapp,
                    .m-video-related,
                    .m-video2-recom,
                    .m-video-related-wrap,
                    .recom-wrapper,
                    .recom-list,
                    .rec-list,
                    .related-list,
                    .video-sections,
                    .up-panel-container,
                    .up-info-container,
                    .video-top-container,
                    .note-card,
                    .bpx-player-sending-area,
                    .bilibili-player-video-inputbar,
                    .bilibili-player-danmaku-input,
                    .bilibili-player-danmaku-send {
                      display: none !important;
                    }

                    #mirror-vdcon.video-container-v1,
                    .video-container-v1,
                    .video-container {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 12px !important;
                      align-items: stretch !important;
                    }

                    .left-container,
                    .left-container.scroll-sticky,
                    .right-container,
                    .right-container-inner {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                      position: static !important;
                      inset: auto !important;
                    }

                    .left-container,
                    .left-container.scroll-sticky {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 12px !important;
                      order: 1 !important;
                    }

                    .right-container,
                    .right-container-inner {
                      order: 2 !important;
                    }

                    .left-container > :not(#playerWrap):not(.player-wrap):not(#arc_toolbar_report):not(.video-toolbar-container):not(#focus-native-video-augment),
                    .left-container.scroll-sticky > :not(#playerWrap):not(.player-wrap):not(#arc_toolbar_report):not(.video-toolbar-container):not(#focus-native-video-augment) {
                      display: none !important;
                    }

                    #playerWrap,
                    .player-wrap,
                    .player-container,
                    #bilibili-player,
                    .bpx-player-container,
                    .bpx-player-video-wrap {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      box-sizing: border-box !important;
                    }

                    @media (orientation: portrait) {
                      html[data-focus-platform='ios'] #playerWrap,
                      html[data-focus-platform='ios'] #bilibili-player,
                      html[data-focus-platform='ios'] .bpx-player-container,
                      html[data-focus-platform='ios'] .player-container,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap {
                        width: 100% !important;
                        max-width: 100% !important;
                        min-height: 0 !important;
                        height: calc(100vw / 1.5) !important;
                        min-height: 0 !important;
                        max-height: none !important;
                        aspect-ratio: 3 / 2 !important;
                        overflow: hidden !important;
                        position: relative !important;
                        background: #000 !important;
                        padding-top: 0 !important;
                        padding-bottom: 0 !important;
                      }

                      html[data-focus-platform='ios'] .bpx-player-primary-area,
                      html[data-focus-platform='ios'] .bpx-player-video-area,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap,
                      html[data-focus-platform='ios'] .bpx-player-video-perch,
                      html[data-focus-platform='ios'] .bpx-player-video-screen,
                      html[data-focus-platform='ios'] .bilibili-player-video,
                      html[data-focus-platform='ios'] .bilibili-player-video-wrap {
                        min-height: 0 !important;
                        height: 100% !important;
                        max-height: 100% !important;
                        overflow: hidden !important;
                        position: relative !important;
                        background: #000 !important;
                        padding-top: 0 !important;
                        padding-bottom: 0 !important;
                      }

                      html[data-focus-platform='ios'] #playerWrap video,
                      html[data-focus-platform='ios'] #bilibili-player video,
                      html[data-focus-platform='ios'] .bpx-player-container video,
                      html[data-focus-platform='ios'] .player-container video,
                      html[data-focus-platform='ios'] .bpx-player-video-wrap video,
                      html[data-focus-platform='ios'] .bpx-player-video-area video,
                      html[data-focus-platform='ios'] .bilibili-player-video video {
                        width: 100% !important;
                        height: 100% !important;
                        min-height: 100% !important;
                        max-height: 100% !important;
                        object-fit: contain !important;
                        display: block !important;
                      }
                    }

                    .bpx-player-control-wrap,
                    .bpx-player-control-bottom,
                    .bpx-player-control-bottom-left,
                    .bpx-player-control-bottom-right,
                    .bpx-player-ctrl-bottom,
                    .bpx-player-ctrl-bottom-left,
                    .bpx-player-ctrl-bottom-right {
                      opacity: 1 !important;
                      visibility: visible !important;
                      transform: none !important;
                      pointer-events: auto !important;
                    }

                    .bpx-player-control-wrap,
                    .bpx-player-control-bottom,
                    .bpx-player-ctrl-bottom {
                      background: linear-gradient(180deg, transparent 0%, rgba(0, 0, 0, 0.72) 100%) !important;
                    }

                    .bpx-player-control-wrap [class*="playbackrate"],
                    .bpx-player-control-wrap [class*="dm-switch"],
                    .bpx-player-control-wrap [class*="ctrl-dm"],
                    .bpx-player-control-wrap [class*="subtitle"],
                    .bpx-player-control-wrap [class*="ctrl-full"],
                    .bpx-player-control-wrap [class*="fullscreen"],
                    .bpx-player-ctrl-playbackrate,
                    .bpx-player-dm-switch,
                    .bpx-player-ctrl-dm,
                    .bpx-player-ctrl-subtitle,
                    .bpx-player-ctrl-full {
                      display: inline-flex !important;
                      opacity: 1 !important;
                      visibility: visible !important;
                    }

                    .focus-hide-danmaku .bpx-player-row-dm-wrap,
                    .focus-hide-danmaku .bpx-player-video-dm-wrap,
                    .focus-hide-danmaku .bpx-player-dm-wrap,
                    .focus-hide-danmaku .bilibili-player-video-danmaku {
                      display: none !important;
                    }

                    .focus-hide-subtitles .bpx-player-subtitle-wrap,
                    .focus-hide-subtitles [class*="subtitle-item"],
                    .focus-hide-subtitles [class*="subtitle-wrap"] {
                      display: none !important;
                    }

                    #arc_toolbar_report,
                    .video-toolbar-container {
                      display: block !important;
                      width: auto !important;
                      min-width: 0 !important;
                      max-width: none !important;
                      margin: 4px 16px 4px !important;
                      padding: 12px 16px !important;
                      box-sizing: border-box !important;
                      background: rgba(248, 250, 252, 0.96) !important;
                      background-image: none !important;
                      border: 1px solid rgba(15, 23, 42, 0.06) !important;
                      border-radius: 20px !important;
                      box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
                    }

                    html[data-focus-theme='dark'] #arc_toolbar_report,
                    html[data-focus-theme='dark'] .video-toolbar-container {
                      background: rgba(17, 24, 39, 0.96) !important;
                      border-color: rgba(255, 255, 255, 0.08) !important;
                      box-shadow: 0 12px 24px rgba(0, 0, 0, 0.22) !important;
                    }

                    #arc_toolbar_report::before,
                    #arc_toolbar_report::after,
                    .video-toolbar-container::before,
                    .video-toolbar-container::after {
                      display: none !important;
                      content: none !important;
                      background: transparent !important;
                      border: 0 !important;
                      box-shadow: none !important;
                    }

                    #arc_toolbar_report .video-toolbar-right,
                    .video-toolbar-container .video-toolbar-right,
                    #arc_toolbar_report .toolbar-right,
                    .video-toolbar-container .toolbar-right {
                      display: none !important;
                    }

                    #arc_toolbar_report .video-toolbar-left,
                    .video-toolbar-container .video-toolbar-left,
                    #arc_toolbar_report .toolbar-left,
                    .video-toolbar-container .toolbar-left {
                      display: block !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      background: transparent !important;
                      border: 0 !important;
                      box-shadow: none !important;
                    }

                    #arc_toolbar_report .video-toolbar-left-main,
                    .video-toolbar-container .video-toolbar-left-main,
                    #arc_toolbar_report .toolbar-left-main,
                    .video-toolbar-container .toolbar-left-main {
                      display: flex !important;
                      flex-direction: row !important;
                      align-items: center !important;
                      justify-content: stretch !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      background: transparent !important;
                      border: 0 !important;
                      box-shadow: none !important;
                    }

                    #arc_toolbar_report .video-toolbar-left-main > *,
                    .video-toolbar-container .video-toolbar-left-main > *,
                    #arc_toolbar_report .toolbar-left-main > *,
                    .video-toolbar-container .toolbar-left-main > * {
                      flex: 1 1 0 !important;
                      display: flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      width: 0 !important;
                      min-width: 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                    }

                    #arc_toolbar_report .toolbar-left-item-wrap,
                    .video-toolbar-container .toolbar-left-item-wrap {
                      flex: 1 1 0 !important;
                      width: 0 !important;
                      min-width: 0 !important;
                    }

                    #arc_toolbar_report .video-toolbar-left > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    .video-toolbar-container .video-toolbar-left > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    #arc_toolbar_report .video-toolbar-left-main > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    .video-toolbar-container .video-toolbar-left-main > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    #arc_toolbar_report .toolbar-left > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    .video-toolbar-container .toolbar-left > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    #arc_toolbar_report .toolbar-left-main > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    .video-toolbar-container .toolbar-left-main > *:has(.video-complaint, [class*="complaint"], [class*="more"]),
                    #arc_toolbar_report .video-share-wrap,
                    .video-toolbar-container .video-share-wrap,
                    #arc_toolbar_report .toolbar-left-item-wrap:has(.video-share-wrap),
                    .video-toolbar-container .toolbar-left-item-wrap:has(.video-share-wrap) {
                      display: none !important;
                    }

                    #arc_toolbar_report .video-like-info,
                    .video-toolbar-container .video-like-info,
                    #arc_toolbar_report .video-like,
                    .video-toolbar-container .video-like,
                    #arc_toolbar_report .video-coin,
                    .video-toolbar-container .video-coin,
                    #arc_toolbar_report .video-fav,
                    .video-toolbar-container .video-fav,
                    #arc_toolbar_report .video-share-wrap,
                    .video-toolbar-container .video-share-wrap {
                      width: auto !important;
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      gap: 0 !important;
                      background: transparent !important;
                      border: 0 !important;
                      box-shadow: none !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      min-width: 0 !important;
                      text-align: center !important;
                      line-height: 1 !important;
                    }

                    #arc_toolbar_report .video-like-info > *,
                    .video-toolbar-container .video-like-info > *,
                    #arc_toolbar_report .video-like > *,
                    .video-toolbar-container .video-like > *,
                    #arc_toolbar_report .video-coin > *,
                    .video-toolbar-container .video-coin > *,
                    #arc_toolbar_report .video-fav > *,
                    .video-toolbar-container .video-fav > *,
                    #arc_toolbar_report .video-share-wrap > *,
                    .video-toolbar-container .video-share-wrap > * {
                      margin: 0 !important;
                      padding: 0 !important;
                    }

                    #arc_toolbar_report .video-like-info svg,
                    .video-toolbar-container .video-like-info svg,
                    #arc_toolbar_report .video-like svg,
                    .video-toolbar-container .video-like svg,
                    #arc_toolbar_report .video-coin svg,
                    .video-toolbar-container .video-coin svg,
                    #arc_toolbar_report .video-fav svg,
                    .video-toolbar-container .video-fav svg,
                    #arc_toolbar_report .video-share-wrap svg,
                    .video-toolbar-container .video-share-wrap svg,
                    #arc_toolbar_report .video-like-info i,
                    .video-toolbar-container .video-like-info i,
                    #arc_toolbar_report .video-coin i,
                    .video-toolbar-container .video-coin i,
                    #arc_toolbar_report .video-fav i,
                    .video-toolbar-container .video-fav i,
                    #arc_toolbar_report .video-share-wrap i,
                    .video-toolbar-container .video-share-wrap i {
                      flex: 0 0 auto !important;
                      margin: 0 !important;
                      display: inline-flex !important;
                      visibility: visible !important;
                      opacity: 1 !important;
                    }

                    #arc_toolbar_report .video-like-info span,
                    .video-toolbar-container .video-like-info span,
                    #arc_toolbar_report .video-like span,
                    .video-toolbar-container .video-like span,
                    #arc_toolbar_report .video-coin span,
                    .video-toolbar-container .video-coin span,
                    #arc_toolbar_report .video-fav span,
                    .video-toolbar-container .video-fav span {
                      display: none !important;
                      visibility: hidden !important;
                      opacity: 0 !important;
                      width: 0 !important;
                      height: 0 !important;
                      max-width: 0 !important;
                      max-height: 0 !important;
                      overflow: hidden !important;
                      position: absolute !important;
                      pointer-events: none !important;
                      flex: 0 0 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      border: 0 !important;
                      font-size: 0 !important;
                      line-height: 0 !important;
                    }

                    #arc_toolbar_report .video-share-wrap span span,
                    .video-toolbar-container .video-share-wrap span span,
                    #arc_toolbar_report .video-share-wrap .video-share span,
                    .video-toolbar-container .video-share-wrap .video-share span {
                      display: none !important;
                      visibility: hidden !important;
                      opacity: 0 !important;
                      width: 0 !important;
                      height: 0 !important;
                      max-width: 0 !important;
                      max-height: 0 !important;
                      overflow: hidden !important;
                      position: absolute !important;
                      pointer-events: none !important;
                      flex: 0 0 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                      border: 0 !important;
                      font-size: 0 !important;
                      line-height: 0 !important;
                    }

                    #arc_toolbar_report .video-share-wrap > span,
                    .video-toolbar-container .video-share-wrap > span {
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      gap: 0 !important;
                      min-width: 0 !important;
                      width: auto !important;
                    }

                    #arc_toolbar_report .video-share-wrap > span > .video-share-popover,
                    .video-toolbar-container .video-share-wrap > span > .video-share-popover,
                    #arc_toolbar_report .video-share-wrap > span > :not(.video-share),
                    .video-toolbar-container .video-share-wrap > span > :not(.video-share) {
                      display: none !important;
                    }

                    #arc_toolbar_report .video-share-wrap > span > .video-share,
                    .video-toolbar-container .video-share-wrap > span > .video-share {
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      gap: 0 !important;
                      margin: 0 !important;
                      padding: 0 !important;
                    }

                    .right-container:not(:has(.video-pod)),
                    .right-container-inner:not(:has(.video-pod)) {
                      display: none !important;
                    }

                    .right-container:has(.video-pod),
                    .right-container-inner:has(.video-pod) {
                      display: block !important;
                      order: 3 !important;
                    }

                    .right-container > *:not(.video-pod):not(:has(.video-pod)),
                    .right-container-inner > *:not(.video-pod):not(:has(.video-pod)) {
                      display: none !important;
                    }

                    .right-container > *:has(.video-pod),
                    .right-container-inner > *:has(.video-pod),
                    .right-container > *:has(.video-pod) > *:has(.video-pod),
                    .right-container-inner > *:has(.video-pod) > *:has(.video-pod) {
                      display: block !important;
                      width: 100% !important;
                      max-width: 100% !important;
                      margin: 0 !important;
                      padding: 0 !important;
                    }

                    .right-container > *:has(.video-pod) > *:not(.video-pod):not(:has(.video-pod)),
                    .right-container-inner > *:has(.video-pod) > *:not(.video-pod):not(:has(.video-pod)),
                    .right-container > *:has(.video-pod) > *:has(.video-pod) > *:not(.video-pod):not(:has(.video-pod)),
                    .right-container-inner > *:has(.video-pod) > *:has(.video-pod) > *:not(.video-pod):not(:has(.video-pod)) {
                      display: none !important;
                    }

                    .video-pod,
                    .video-pod__header,
                    .video-pod__body,
                    .video-pod__slide,
                    .video-pod__list,
                    .video-pod__list.multip.list {
                      width: 100% !important;
                      min-width: 0 !important;
                      max-width: 100% !important;
                      box-sizing: border-box !important;
                    }

                    .video-pod {
                      margin: 0 12px 14px !important;
                      padding: 12px !important;
                      border: 1px solid #e4e9f2 !important;
                      border-radius: 18px !important;
                      background: #f5f7fb !important;
                      box-shadow: 0 10px 24px rgba(15, 23, 42, 0.06) !important;
                    }

                    .video-pod__header {
                      display: flex !important;
                      align-items: center !important;
                      justify-content: space-between !important;
                      gap: 10px !important;
                      flex-wrap: wrap !important;
                      margin: 0 0 8px !important;
                      padding: 0 !important;
                      font-size: 17px !important;
                      font-weight: 700 !important;
                      color: #111827 !important;
                    }

                    .video-pod__body > :not(.video-pod__slide):not(.video-pod__list):not(:has(.video-pod__list)) {
                      display: none !important;
                    }

                    .video-pod__list,
                    .video-pod__list.multip.list {
                      display: flex !important;
                      flex-direction: column !important;
                      gap: 7px !important;
                      max-height: none !important;
                      overflow: visible !important;
                    }

                    .video-pod__item,
                    .video-pod__list .video-pod__item,
                    .video-pod__list .pod-item {
                      display: flex !important;
                      align-items: center !important;
                      justify-content: space-between !important;
                      gap: 12px !important;
                      width: 100% !important;
                      margin: 0 !important;
                      padding: 10px 12px !important;
                      border: 1px solid #dbe3ef !important;
                      border-radius: 14px !important;
                      background: #fff !important;
                      box-shadow: 0 6px 16px rgba(15, 23, 42, 0.05) !important;
                    }

                    .video-pod__item > *,
                    .video-pod__list .video-pod__item > *,
                    .video-pod__list .pod-item > * {
                      min-width: 0 !important;
                    }

                    .video-pod__item [class*="title"],
                    .video-pod__item .title,
                    .video-pod__item .part,
                    .video-pod__list .video-pod__item [class*="title"],
                    .video-pod__list .pod-item [class*="title"] {
                      flex: 1 1 auto !important;
                      min-width: 0 !important;
                      overflow: hidden !important;
                      text-overflow: ellipsis !important;
                      white-space: nowrap !important;
                    }

                    .video-pod__item [class*="duration"],
                    .video-pod__item [class*="time"],
                    .video-pod__item .duration,
                    .video-pod__item .time,
                    .video-pod__list .pod-item [class*="duration"],
                    .video-pod__list .pod-item [class*="time"] {
                      flex: 0 0 auto !important;
                      color: #6b7280 !important;
                      font-weight: 600 !important;
                    }

                    [data-focus-video-pod-toggle] {
                      display: inline-flex !important;
                      align-items: center !important;
                      justify-content: center !important;
                      width: 100% !important;
                      min-height: 42px !important;
                      margin: 10px 0 0 !important;
                      padding: 0 14px !important;
                      border: 0 !important;
                      border-radius: 14px !important;
                      background: #eaf2ff !important;
                      color: #126fd6 !important;
                      font-size: 14px !important;
                      font-weight: 700 !important;
                    }

                    [data-focus-video-pod-toggle][data-expanded="true"] {
                      background: #eef2f7 !important;
                      color: #4b5563 !important;
                    }

                    .video-pod__item.active,
                    .video-pod__item.on,
                    .video-pod__item.is-active,
                    .video-pod__list .on,
                    .video-pod__list .active {
                      border-color: #7cc2ff !important;
                      background: #ecf7ff !important;
                      color: #0f6ecf !important;
                    }
                    """,
                    script: """
                    const state = helpers.featureState;

                    const playerSelectors = {
                      shell: '#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap',
                      playButton: '.bpx-player-ctrl-play, .bilibili-player-video-btn-start, [class*="ctrl-play"]',
                      danmakuToggle: '.bpx-player-ctrl-dm, .bpx-player-dm-switch, [class*="dm-switch"], [class*="ctrl-dm"]',
                      subtitleToggle: '.bpx-player-ctrl-subtitle, .bpx-player-subtitle-btn, [class*="subtitle-switch"], [class*="subtitle-btn"], [class*="subtitle"] button',
                      playbackRateNode: '.bpx-player-ctrl-playbackrate-result, .bpx-player-ctrl-playbackrate [class*="name"], .bpx-player-ctrl-playbackrate [class*="text"], .bpx-player-ctrl-playbackrate-menu .active, [class*="playbackrate"] [class*="name"], [class*="playbackrate"] [class*="text"], [class*="playbackrate"], [class*="speed"] .active, [class*="speed"] [aria-checked="true"]',
                      subtitleLayer: '.bpx-player-subtitle-wrap, [class*="subtitle-panel"], [class*="subtitle-item"], [class*="subtitle-wrap"]'
                    };

                    state.videoPodCollapsed = state.videoPodCollapsed !== false;
                    const pageKey = `${location.pathname}${location.search}`;
                    if (state.autoplayPageKey !== pageKey) {
                      state.autoplayPageKey = pageKey;
                      state.autoplayDefaultHandled = false;
                    }

                    const trackedVideo = () => {
                      const candidate = window.__FOCUS_ACTIVE_VIDEO__;
                      if (candidate && candidate.isConnected && candidate.ownerDocument === document) {
                        return candidate;
                      }
                      return null;
                    };

                    const rememberActiveVideo = (video) => {
                      if (video && video.isConnected && video.ownerDocument === document) {
                        window.__FOCUS_ACTIVE_VIDEO__ = video;
                        return video;
                      }
                      return null;
                    };

                    const isIOSFocus = document.documentElement?.getAttribute?.('data-focus-platform') === 'ios';
                    state.iosPlayerSizingSuppressedUntil = Number.isFinite(state.iosPlayerSizingSuppressedUntil)
                      ? state.iosPlayerSizingSuppressedUntil
                      : 0;
                    state.iosPlayerLayoutMode = state.iosPlayerLayoutMode === 'expanded'
                      ? 'expanded'
                      : 'automatic';
                    state.iosPlayerLayoutReleaseToken = Number.isFinite(state.iosPlayerLayoutReleaseToken)
                      ? state.iosPlayerLayoutReleaseToken
                      : 0;

                    const iosPlayerShellSelectors = [
                      '#playerWrap',
                      '#bilibili-player',
                      '.bpx-player-container',
                      '.player-container',
                      '.bpx-player-video-wrap'
                    ];
                    const iosPlayerContentSelectors = [
                      '.bpx-player-primary-area',
                      '.bpx-player-video-area',
                      '.bpx-player-video-wrap',
                      '.bpx-player-video-perch',
                      '.bpx-player-video-screen',
                      '.bilibili-player-video',
                      '.bilibili-player-video-wrap'
                    ];
                    const iosPlayerVideoSelectors = [
                      '#playerWrap video',
                      '#bilibili-player video',
                      '.bpx-player-container video',
                      '.player-container video',
                      '.bpx-player-video-wrap video',
                      '.bpx-player-video-area video',
                      '.bilibili-player-video video'
                    ];

                    const clearIOSPlayerSizing = () => {
                      if (!isIOSFocus) {
                        return;
                      }

                      [
                        ...iosPlayerShellSelectors,
                        ...iosPlayerContentSelectors,
                        ...iosPlayerVideoSelectors
                      ].forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          [
                            'width',
                            'min-width',
                            'max-width',
                            'height',
                            'min-height',
                            'max-height',
                            'aspect-ratio',
                            'overflow',
                            'padding-top',
                            'padding-bottom',
                            'background',
                            'position',
                            'display',
                            'align-items',
                            'justify-content',
                            'margin',
                            'margin-left',
                            'margin-right',
                            'margin-top',
                            'margin-bottom',
                            'object-position',
                            'object-fit',
                            'transform',
                            'left',
                            'top',
                            'right',
                            'bottom',
                            'inset',
                            'z-index'
                          ].forEach((property) => {
                            node.style.removeProperty(property);
                          });
                        });
                      });
                      document.documentElement.removeAttribute('data-focus-player-layout');
                    };

                    const iosViewportSize = () => {
                      const widths = [
                        window.visualViewport?.width || 0,
                        window.innerWidth || 0,
                        document.documentElement?.clientWidth || 0
                      ].filter((value) => Number.isFinite(value) && value > 0);
                      const heights = [
                        window.visualViewport?.height || 0,
                        window.innerHeight || 0,
                        document.documentElement?.clientHeight || 0
                      ].filter((value) => Number.isFinite(value) && value > 0);
                      return {
                        width: widths.length > 0 ? Math.round(Math.min(...widths)) : 0,
                        height: heights.length > 0 ? Math.round(Math.min(...heights)) : 0
                      };
                    };

                    const isLandscapeViewport = () => {
                      const viewportWidth = window.innerWidth || document.documentElement?.clientWidth || window.visualViewport?.width || 0;
                      const viewportHeight = window.innerHeight || document.documentElement?.clientHeight || window.visualViewport?.height || 0;
                      return window.matchMedia?.('(orientation: landscape)')?.matches === true
                        || (viewportWidth > 0 && viewportHeight > 0 && viewportWidth > viewportHeight);
                    };

                    const rankVideos = () => {
                      return Array.from(document.querySelectorAll('video'))
                        .map((video) => {
                          const rect = video.getBoundingClientRect();
                          const style = window.getComputedStyle(video);
                          const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                          const visible = rect.width > 120
                            && rect.height > 70
                            && style.display !== 'none'
                            && style.visibility !== 'hidden'
                            && style.opacity !== '0';
                          const insidePlayer = !!video.closest(playerSelectors.shell);
                          const largePlaybackCandidate = rect.width >= Math.max(window.innerWidth * 0.62, 240)
                            || rect.height >= 180
                            || area >= 65000;
                          const score = (insidePlayer ? 1000000 : 0)
                            + (largePlaybackCandidate ? 250000 : 0)
                            + (visible ? 100000 : 0)
                            + area
                            + (video.readyState > 0 ? 5000 : 0)
                            + (!video.paused && !video.ended ? 1000 : 0);
                          return { video, score, largePlaybackCandidate, insidePlayer };
                        })
                        .sort((left, right) => right.score - left.score);
                    };

                    const findPrimaryVideo = () => {
                      const currentTrackedVideo = trackedVideo();
                      if (currentTrackedVideo) {
                        return rememberActiveVideo(currentTrackedVideo);
                      }

                      const rankedVideos = rankVideos();
                      return rememberActiveVideo(rankedVideos[0]?.video || null);
                    };

                    const isIOSPlayerFullscreen = (activeVideo, playerRoot) => {
                      return !!document.fullscreenElement
                        || activeVideo?.webkitPresentationMode === 'fullscreen'
                        || activeVideo?.webkitPresentationMode === 'fullScreen'
                        || activeVideo?.webkitDisplayingFullscreen === true
                        || /(^|\\s)(?:web-)?fullscreen(?:\\s|$)/.test(String(playerRoot?.className || ''));
                    };

                    const applyIOSExpandedPlayerSizing = (playerRoot) => {
                      const currentVideo = trackedVideo() || playerRoot.querySelector('video');
                      const videoStyle = currentVideo instanceof HTMLElement ? window.getComputedStyle(currentVideo) : null;
                      const layoutIsCurrent = document.documentElement.getAttribute('data-focus-player-layout') === 'expanded'
                        && playerRoot.style.getPropertyValue('position') === 'fixed'
                        && playerRoot.style.getPropertyValue('width') === '100vw'
                        && playerRoot.style.getPropertyValue('height') === '100vh'
                        && (!videoStyle || (
                          videoStyle.position === 'absolute'
                          && videoStyle.objectPosition === '50% 50%'
                        ));
                      if (layoutIsCurrent) {
                        return;
                      }

                      clearIOSPlayerSizing();
                      document.documentElement.setAttribute('data-focus-player-layout', 'expanded');
                      const viewportWidth = '100vw';
                      const viewportHeight = '100vh';

                      iosPlayerShellSelectors.forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('width', viewportWidth, 'important');
                          node.style.setProperty('min-width', viewportWidth, 'important');
                          node.style.setProperty('max-width', viewportWidth, 'important');
                          node.style.setProperty('height', viewportHeight, 'important');
                          node.style.setProperty('min-height', viewportHeight, 'important');
                          node.style.setProperty('max-height', viewportHeight, 'important');
                          node.style.setProperty('aspect-ratio', 'auto', 'important');
                          node.style.setProperty('overflow', 'hidden', 'important');
                          node.style.setProperty('padding-top', '0', 'important');
                          node.style.setProperty('padding-bottom', '0', 'important');
                          node.style.setProperty('background', '#000', 'important');
                          node.style.setProperty('margin', '0', 'important');
                          node.style.setProperty('position', 'relative', 'important');
                          node.style.setProperty('display', 'flex', 'important');
                          node.style.setProperty('align-items', 'center', 'important');
                          node.style.setProperty('justify-content', 'center', 'important');
                        });
                      });

                      playerRoot.style.setProperty('position', 'fixed', 'important');
                      playerRoot.style.setProperty('left', '0', 'important');
                      playerRoot.style.setProperty('top', '0', 'important');
                      playerRoot.style.setProperty('right', '0', 'important');
                      playerRoot.style.setProperty('bottom', '0', 'important');
                      playerRoot.style.setProperty('z-index', '2147483000', 'important');

                      iosPlayerContentSelectors.forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('width', '100%', 'important');
                          node.style.setProperty('min-width', '100%', 'important');
                          node.style.setProperty('max-width', '100%', 'important');
                          node.style.setProperty('height', '100%', 'important');
                          node.style.setProperty('min-height', '100%', 'important');
                          node.style.setProperty('max-height', '100%', 'important');
                          node.style.setProperty('overflow', 'hidden', 'important');
                          node.style.setProperty('position', 'relative', 'important');
                          node.style.setProperty('display', 'flex', 'important');
                          node.style.setProperty('align-items', 'center', 'important');
                          node.style.setProperty('justify-content', 'center', 'important');
                          node.style.setProperty('background', '#000', 'important');
                          node.style.setProperty('padding-top', '0', 'important');
                          node.style.setProperty('padding-bottom', '0', 'important');
                        });
                      });

                      iosPlayerVideoSelectors.forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('width', '100%', 'important');
                          node.style.setProperty('min-width', '100%', 'important');
                          node.style.setProperty('max-width', '100%', 'important');
                          node.style.setProperty('height', '100%', 'important');
                          node.style.setProperty('min-height', '100%', 'important');
                          node.style.setProperty('max-height', '100%', 'important');
                          node.style.setProperty('display', 'block', 'important');
                          node.style.setProperty('position', 'absolute', 'important');
                          node.style.setProperty('inset', '0', 'important');
                          node.style.setProperty('margin', 'auto', 'important');
                          node.style.setProperty('object-fit', 'contain', 'important');
                          node.style.setProperty('object-position', 'center center', 'important');
                          node.style.setProperty('transform', 'none', 'important');
                        });
                      });
                    };

                    const applyIOSPlayerSizing = () => {
                      if (!isIOSFocus) {
                        return;
                      }

                      const activeVideo = findPrimaryVideo();
                      const playerRoot = document.querySelector('#playerWrap, #bilibili-player, .bpx-player-container, .player-container');
                      if (!(playerRoot instanceof HTMLElement)) {
                        return;
                      }

                      const shouldUseExpandedLayout = state.iosPlayerLayoutMode === 'expanded'
                        || isIOSPlayerFullscreen(activeVideo, playerRoot)
                        || isLandscapeViewport();
                      if (shouldUseExpandedLayout) {
                        applyIOSExpandedPlayerSizing(playerRoot);
                        return;
                      }

                      if (state.iosPlayerSizingSuppressedUntil > Date.now()) {
                        clearIOSPlayerSizing();
                        document.documentElement.setAttribute('data-focus-player-layout', 'transition');
                        return;
                      }

                      const measuredWidths = [
                        iosViewportSize().width,
                        playerRoot.parentElement?.getBoundingClientRect?.().width || 0,
                        document.querySelector('#app')?.getBoundingClientRect?.().width || 0,
                        document.querySelector('main')?.getBoundingClientRect?.().width || 0
                      ].filter((value) => Number.isFinite(value) && value > 0);
                      const shellWidth = measuredWidths.length > 0 ? Math.min(...measuredWidths) : 0;
                      if (!(shellWidth > 0)) {
                        return;
                      }

                      const targetAspectRatio = 3 / 2;
                      const objectFitMode = 'contain';
                      const widthBasis = Math.round(shellWidth);
                      const targetHeight = Math.max(180, Math.round(widthBasis / targetAspectRatio));

                      const appliedWidth = Number.parseFloat(playerRoot.style.getPropertyValue('width') || '0');
                      const appliedHeight = Number.parseFloat(playerRoot.style.getPropertyValue('height') || '0');
                      const layoutIsCurrent = document.documentElement.getAttribute('data-focus-player-layout') === 'portrait'
                        && playerRoot.style.getPropertyValue('position') !== 'fixed'
                        && Math.abs(appliedWidth - widthBasis) <= 1
                        && Math.abs(appliedHeight - targetHeight) <= 1;
                      if (layoutIsCurrent) {
                        return;
                      }

                      clearIOSPlayerSizing();
                      document.documentElement.setAttribute('data-focus-player-layout', 'portrait');
                      document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
                      document.body?.style?.setProperty('overflow-x', 'hidden', 'important');
                      document.body?.style?.setProperty('width', '100%', 'important');
                      document.body?.style?.setProperty('max-width', '100vw', 'important');

                      [
                        '#playerWrap',
                        '#bilibili-player',
                        '.bpx-player-container',
                        '.player-container',
                        '.bpx-player-video-wrap'
                      ].forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('width', `${widthBasis}px`, 'important');
                          node.style.setProperty('max-width', `${widthBasis}px`, 'important');
                          node.style.setProperty('height', `${targetHeight}px`, 'important');
                          node.style.setProperty('min-height', `${targetHeight}px`, 'important');
                          node.style.setProperty('max-height', `${targetHeight}px`, 'important');
                          node.style.setProperty('aspect-ratio', '3 / 2', 'important');
                          node.style.setProperty('overflow', 'hidden', 'important');
                          node.style.setProperty('padding-top', '0', 'important');
                          node.style.setProperty('padding-bottom', '0', 'important');
                          node.style.setProperty('background', '#000', 'important');
                          node.style.setProperty('margin-left', 'auto', 'important');
                          node.style.setProperty('margin-right', 'auto', 'important');
                        });
                      });

                      [
                        '.bpx-player-primary-area',
                        '.bpx-player-video-area',
                        '.bpx-player-video-wrap',
                        '.bpx-player-video-perch',
                        '.bpx-player-video-screen',
                        '.bilibili-player-video',
                        '.bilibili-player-video-wrap'
                      ].forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('height', `${targetHeight}px`, 'important');
                          node.style.setProperty('min-height', `${targetHeight}px`, 'important');
                          node.style.setProperty('max-height', `${targetHeight}px`, 'important');
                          node.style.setProperty('overflow', 'hidden', 'important');
                          node.style.setProperty('position', 'relative', 'important');
                          node.style.setProperty('display', 'flex', 'important');
                          node.style.setProperty('align-items', 'center', 'important');
                          node.style.setProperty('justify-content', 'center', 'important');
                          node.style.setProperty('background', '#000', 'important');
                          node.style.setProperty('padding-top', '0', 'important');
                          node.style.setProperty('padding-bottom', '0', 'important');
                        });
                      });

                      [
                        '#playerWrap video',
                        '#bilibili-player video',
                        '.bpx-player-container video',
                        '.player-container video',
                        '.bpx-player-video-wrap video',
                        '.bpx-player-video-area video',
                        '.bilibili-player-video video'
                      ].forEach((selector) => {
                        document.querySelectorAll(selector).forEach((node) => {
                          if (!(node instanceof HTMLElement)) {
                            return;
                          }
                          node.style.setProperty('width', '100%', 'important');
                          node.style.setProperty('height', '100%', 'important');
                          node.style.setProperty('min-height', '100%', 'important');
                          node.style.setProperty('max-height', '100%', 'important');
                          node.style.setProperty('display', 'block', 'important');
                          node.style.setProperty('object-fit', objectFitMode, 'important');
                          node.style.setProperty('object-position', 'center center', 'important');
                          node.style.setProperty('transform', 'none', 'important');
                        });
                      });
                    };

                    const setIOSPlayerLayoutMode = (mode = 'automatic') => {
                      if (!isIOSFocus) {
                        return;
                      }

                      state.iosPlayerLayoutMode = mode === 'expanded' ? 'expanded' : 'automatic';
                      state.iosPlayerLayoutReleaseToken += 1;
                      const releaseToken = state.iosPlayerLayoutReleaseToken;
                      applyIOSPlayerSizing();

                      if (state.iosPlayerLayoutMode === 'expanded') {
                        setTimeout(() => {
                          if (releaseToken !== state.iosPlayerLayoutReleaseToken) {
                            return;
                          }
                          const activeVideo = findPrimaryVideo();
                          const playerRoot = document.querySelector('#playerWrap, #bilibili-player, .bpx-player-container, .player-container');
                          if (!(playerRoot instanceof HTMLElement)) {
                            return;
                          }
                          if (!isIOSPlayerFullscreen(activeVideo, playerRoot) && !isLandscapeViewport()) {
                            state.iosPlayerLayoutMode = 'automatic';
                            state.iosPlayerSizingSuppressedUntil = 0;
                            applyIOSPlayerSizing();
                          }
                        }, 1800);
                      }
                    };

                    const suppressIOSPlayerSizing = (duration = 520, layoutMode = null) => {
                      if (!isIOSFocus) {
                        return;
                      }
                      if (layoutMode === 'expanded' || layoutMode === 'automatic') {
                        if (state.iosPlayerLayoutMode !== layoutMode) {
                          setIOSPlayerLayoutMode(layoutMode);
                        }
                      }
                      state.iosPlayerSizingSuppressedUntil = Date.now() + Math.max(duration, 0);
                      applyIOSPlayerSizing();
                    };

                    const collectVideoPodItems = (pod) => {
                      const items = Array.from(pod.querySelectorAll('.video-pod__item, .pod-item'));
                      const deduped = [];
                      const seen = new Set();
                      items.forEach((item) => {
                        if (!(item instanceof HTMLElement)) {
                          return;
                        }
                        if (seen.has(item)) {
                          return;
                        }
                        seen.add(item);
                        deduped.push(item);
                      });
                      return deduped;
                    };

                    const findAutoplayToggle = () => {
                      const selectors = [
                        '.continuous-btn',
                        '[class*="continuous"]',
                        '[class*="autoplay"]',
                        '[class*="auto-play"]'
                      ];
                      for (const selector of selectors) {
                        const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                          const text = String(candidate?.textContent || '').replace(/\\s+/g, '');
                          return text.includes('自动连播') || text.includes('连播');
                        });
                        if (node) {
                          return node;
                        }
                      }
                      return null;
                    };

                    const isAutoplayEnabled = (toggle) => {
                      if (!toggle) {
                        return false;
                      }

                      const switchNode = toggle.querySelector('.switch-btn, [role="switch"], [role="checkbox"], input[type="checkbox"]') || toggle;
                      if ('checked' in switchNode && typeof switchNode.checked === 'boolean') {
                        return !!switchNode.checked;
                      }

                      const ariaChecked = String(switchNode.getAttribute?.('aria-checked') || toggle.getAttribute?.('aria-checked') || '').toLowerCase();
                      const ariaPressed = String(switchNode.getAttribute?.('aria-pressed') || toggle.getAttribute?.('aria-pressed') || '').toLowerCase();
                      const dataState = String(switchNode.getAttribute?.('data-state') || toggle.getAttribute?.('data-state') || '').toLowerCase();
                      const className = String(switchNode.className || toggle.className || '').toLowerCase();

                      if (ariaChecked === 'true' || ariaPressed === 'true') {
                        return true;
                      }

                      if (dataState === 'on' || dataState === 'checked' || dataState === 'active' || dataState === 'enabled') {
                        return true;
                      }

                      return /(^|\\s)(on|active|checked|selected|enabled)(\\s|$)/.test(className);
                    };

                    const normalizeAutoplayDisabled = (toggle) => {
                      if (!toggle) {
                        return;
                      }

                      const switchNode = toggle.querySelector('.switch-btn, [role="switch"], [role="checkbox"], input[type="checkbox"]') || toggle;
                      switchNode.classList?.remove?.('on', 'active', 'checked', 'selected', 'enabled');
                      toggle.classList?.remove?.('on', 'active', 'checked', 'selected', 'enabled');
                      switchNode.setAttribute?.('aria-checked', 'false');
                      switchNode.setAttribute?.('aria-pressed', 'false');
                      switchNode.setAttribute?.('data-state', 'off');
                      toggle.setAttribute?.('aria-checked', 'false');
                      toggle.setAttribute?.('aria-pressed', 'false');
                      toggle.setAttribute?.('data-state', 'off');

                      if ('checked' in switchNode && typeof switchNode.checked === 'boolean') {
                        switchNode.checked = false;
                      }
                    };

                    const disableAutoplayByDefault = () => {
                      if (state.autoplayDefaultHandled) {
                        return;
                      }

                      const toggle = findAutoplayToggle();
                      if (!toggle) {
                        return;
                      }

                      state.autoplayDefaultHandled = true;

                      if (!isAutoplayEnabled(toggle)) {
                        return;
                      }

                      const clickTarget = toggle.querySelector('.switch-btn, [role="switch"], [role="checkbox"], input[type="checkbox"]') || toggle;
                      clickTarget.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                      normalizeAutoplayDisabled(toggle);
                    };

                    const refreshVideoPods = () => {
                      document.querySelectorAll('.video-pod').forEach((pod) => {
                        if (!(pod instanceof HTMLElement)) {
                          return;
                        }

                        const items = collectVideoPodItems(pod);
                        if (items.length === 0) {
                          pod.querySelector('[data-focus-video-pod-toggle]')?.remove();
                          return;
                        }

                        const collapsed = state.videoPodCollapsed !== false;
                        const keepIndices = new Set([0, 1, 2]);
                        const activeIndex = items.findIndex((item) =>
                          item.classList.contains('active')
                          || item.classList.contains('on')
                          || item.classList.contains('is-active')
                          || item.getAttribute('aria-current') === 'true'
                        );
                        if (activeIndex >= 0) {
                          keepIndices.add(activeIndex);
                        }

                        items.forEach((item, index) => {
                          if (collapsed && index >= 3 && !keepIndices.has(index)) {
                            item.style.setProperty('display', 'none', 'important');
                          } else {
                            item.style.removeProperty('display');
                          }
                        });

                        let toggle = pod.querySelector('[data-focus-video-pod-toggle]');
                        if (items.length <= 3) {
                          toggle?.remove();
                          pod.dataset.focusVideoPodCollapsed = 'false';
                          return;
                        }

                        if (!(toggle instanceof HTMLButtonElement)) {
                          toggle = document.createElement('button');
                          toggle.type = 'button';
                          toggle.setAttribute('data-focus-video-pod-toggle', 'true');
                          toggle.addEventListener('click', (event) => {
                            event.preventDefault();
                            event.stopPropagation();
                            state.videoPodCollapsed = !(state.videoPodCollapsed !== false);
                            refreshVideoPods();
                          });
                          const body = pod.querySelector('.video-pod__body');
                          (body instanceof HTMLElement ? body : pod).appendChild(toggle);
                        }

                        toggle.dataset.expanded = collapsed ? 'false' : 'true';
                        toggle.textContent = collapsed
                          ? `展开全部 ${items.length} 条`
                          : '收起分P列表';
                        pod.dataset.focusVideoPodCollapsed = collapsed ? 'true' : 'false';
                      });
                    };

                    const snapshotPlayerState = () => {
                      applyIOSPlayerSizing();
                      const titleSelectors = [
                        '#viewbox_report',
                        'h1.video-title',
                        'h1[class*="video-title"]',
                        '.video-title',
                        '[class*="video-title"]',
                        '[class*="archive-title"]',
                        '.media-title'
                      ];
                      const extractVideoTitle = () => {
                        for (const selector of titleSelectors) {
                          const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                            const text = String(candidate?.textContent || '').trim();
                            const rect = candidate?.getBoundingClientRect?.();
                            return !!text && text.length >= 4 && text.length <= 160 && !!rect && rect.width > 40;
                          });
                          if (node) {
                            return String(node.textContent || '').trim();
                          }
                        }
                        return '';
                      };
                      const activeVideo = findPrimaryVideo();
                      const playerRoot = document.querySelector('.bpx-player-container, #bilibili-player, #playerWrap');
                      const playerRect = playerRoot?.getBoundingClientRect?.();
                      const playButton = document.querySelector(playerSelectors.playButton);
                      const danmakuToggle = document.querySelector(playerSelectors.danmakuToggle);
                      const subtitleToggle = document.querySelector(playerSelectors.subtitleToggle);
                      const playbackRateNode = document.querySelector(playerSelectors.playbackRateNode);
                      const textTracks = activeVideo && activeVideo.textTracks ? Array.from(activeVideo.textTracks) : [];
                      const hasPlayerShell = !!document.querySelector(playerSelectors.shell);
                      const rankedVideos = rankVideos();
                      const primaryRankedVideo = rankedVideos[0] || null;
                      const hasPlayer = hasPlayerShell || !!(primaryRankedVideo && (primaryRankedVideo.insidePlayer || primaryRankedVideo.largePlaybackCandidate));
                      const playerClassName = String(playerRoot?.className || '');
                      const playButtonDescriptor = [
                        playButton?.getAttribute('aria-label'),
                        playButton?.getAttribute('title'),
                        playButton?.textContent,
                        playButton?.className
                      ].filter(Boolean).join(' ').toLowerCase();
                      const uiSuggestsPlaying = /pause|暂停|icon-pause|state-pause|video-state-pause/.test(playButtonDescriptor);
                      const uiSuggestsPaused = /play|播放|icon-play|state-play|video-state-play/.test(playButtonDescriptor);
                      const videoSuggestsPlaying = !!activeVideo && !activeVideo.paused && !activeVideo.ended;
                      const rateText = String(playbackRateNode?.textContent || '').trim();
                      const rateMatch = rateText.match(/(\\d+(?:\\.\\d+)?)\\s*x/i);
                      const parsedRate = rateMatch ? Number(rateMatch[1]) : NaN;
                      const rawPlaybackRate = Number(activeVideo?.playbackRate || 0);
                      const isDanmakuHidden = document.documentElement.classList.contains('focus-hide-danmaku')
                        || danmakuToggle?.getAttribute('aria-checked') === 'false'
                        || danmakuToggle?.getAttribute('aria-pressed') === 'false'
                        || danmakuToggle?.classList.contains('off')
                        || danmakuToggle?.classList.contains('disabled');
                      const hasSubtitles = !!subtitleToggle
                        || !!document.querySelector(playerSelectors.subtitleLayer)
                        || textTracks.length > 0;
                      const isSubtitleHidden = document.documentElement.classList.contains('focus-hide-subtitles')
                        || (textTracks.length > 0 && textTracks.every((track) => track.mode === 'disabled'))
                        || subtitleToggle?.getAttribute('aria-checked') === 'false'
                        || subtitleToggle?.getAttribute('aria-pressed') === 'false'
                        || subtitleToggle?.classList.contains('off')
                        || subtitleToggle?.classList.contains('disabled');

                      const payload = {
                        hasPlayer,
                        pageURL: location.href,
                        pageTitle: document.title || '',
                        videoTitle: extractVideoTitle(),
                        playerWidth: Number.isFinite(playerRect?.width) ? Math.round(playerRect.width) : 0,
                        playerHeight: Number.isFinite(playerRect?.height) ? Math.round(playerRect.height) : 0,
                        isPlaying: activeVideo ? videoSuggestsPlaying : uiSuggestsPlaying && !uiSuggestsPaused,
                        playbackRate: Number.isFinite(rawPlaybackRate) && rawPlaybackRate > 0
                          ? rawPlaybackRate
                          : Number.isFinite(parsedRate) && parsedRate > 0
                              ? parsedRate
                              : 1,
                        isDanmakuHidden: !!isDanmakuHidden,
                        hasSubtitles: !!hasSubtitles,
                        isSubtitleHidden: !!isSubtitleHidden,
                        isFullscreen: !!document.fullscreenElement
                          || activeVideo?.webkitPresentationMode === 'fullscreen'
                          || activeVideo?.webkitPresentationMode === 'fullScreen'
                          || activeVideo?.webkitDisplayingFullscreen === true
                          || /(^|\\s)(?:web-)?fullscreen(?:\\s|$)/.test(playerClassName),
                        updatedAt: Date.now()
                      };

                      window.__FOCUS_PLAYER_STATE__ = payload;
                      try {
                        window.__FOCUS_PLAYER_STATE_LISTENER__?.(payload);
                      } catch (_) {}
                      return payload;
                    };

                      window.__FOCUS_SNAPSHOT_PLAYER_STATE__ = snapshotPlayerState;
                      window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__ = clearIOSPlayerSizing;
                      window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__ = suppressIOSPlayerSizing;
                      window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__ = setIOSPlayerLayoutMode;
                      disableAutoplayByDefault();
                      applyIOSPlayerSizing();
                      snapshotPlayerState();

                    if (!state.playerHooksInstalled) {
                      state.playerHooksInstalled = true;

                      let snapshotTimer = null;
                      let videoPodRefreshTimer = null;
                      let autoplayRefreshTimer = null;
                      let iosPlayerSizingTimer = null;
                      const scheduleSnapshot = (delay = 80) => {
                        clearTimeout(snapshotTimer);
                        snapshotTimer = setTimeout(() => {
                          snapshotPlayerState();
                        }, delay);
                      };
                      const scheduleVideoPodRefresh = (delay = 90) => {
                        clearTimeout(videoPodRefreshTimer);
                        videoPodRefreshTimer = setTimeout(() => {
                          refreshVideoPods();
                        }, delay);
                      };
                      const scheduleAutoplayRefresh = (delay = 90) => {
                        clearTimeout(autoplayRefreshTimer);
                        autoplayRefreshTimer = setTimeout(() => {
                          disableAutoplayByDefault();
                        }, delay);
                      };
                      const scheduleIOSPlayerSizing = (delay = 90) => {
                        clearTimeout(iosPlayerSizingTimer);
                        iosPlayerSizingTimer = setTimeout(() => {
                          applyIOSPlayerSizing();
                        }, delay);
                      };

                      [
                        'play',
                        'pause',
                        'playing',
                        'ratechange',
                        'loadedmetadata',
                        'durationchange',
                        'volumechange',
                        'fullscreenchange',
                        'webkitbeginfullscreen',
                        'webkitendfullscreen',
                        'webkitpresentationmodechanged'
                      ].forEach((eventName) => {
                        document.addEventListener(eventName, (event) => {
                          if (event.target instanceof HTMLVideoElement) {
                            rememberActiveVideo(event.target);
                          }
                          if (eventName === 'webkitbeginfullscreen' || eventName === 'fullscreenchange') {
                            const eventVideo = event.target instanceof HTMLVideoElement ? event.target : trackedVideo();
                            const eventPlayerRoot = eventVideo?.closest?.('#playerWrap, #bilibili-player, .bpx-player-container, .player-container');
                            const enteringFullscreen = !!document.fullscreenElement
                              || eventVideo?.webkitPresentationMode === 'fullscreen'
                              || eventVideo?.webkitPresentationMode === 'fullScreen'
                              || eventVideo?.webkitDisplayingFullscreen === true
                              || /(^|\\s)(?:web-)?fullscreen(?:\\s|$)/.test(String(eventPlayerRoot?.className || ''));
                            if (enteringFullscreen) {
                              setIOSPlayerLayoutMode('expanded');
                              suppressIOSPlayerSizing(1400, 'expanded');
                            } else if (eventName === 'fullscreenchange') {
                              setIOSPlayerLayoutMode('automatic');
                              suppressIOSPlayerSizing(520, 'automatic');
                            }
                          } else if (eventName === 'webkitendfullscreen' || eventName === 'webkitpresentationmodechanged') {
                            const eventVideo = event.target instanceof HTMLVideoElement ? event.target : trackedVideo();
                            const stillFullscreen = eventVideo?.webkitPresentationMode === 'fullscreen'
                              || eventVideo?.webkitPresentationMode === 'fullScreen'
                              || eventVideo?.webkitDisplayingFullscreen === true;
                            if (stillFullscreen) {
                              setIOSPlayerLayoutMode('expanded');
                              suppressIOSPlayerSizing(1400, 'expanded');
                            } else {
                              setIOSPlayerLayoutMode('automatic');
                              suppressIOSPlayerSizing(520, 'automatic');
                            }
                          }
                          scheduleIOSPlayerSizing(eventName === 'loadedmetadata' || eventName === 'webkitendfullscreen' ? 30 : 80);
                          scheduleSnapshot(eventName === 'ratechange' ? 20 : 80);
                        }, true);
                      });

                      window.addEventListener('resize', () => {
                        applyIOSPlayerSizing();
                        scheduleIOSPlayerSizing(30);
                        scheduleSnapshot(60);
                      }, { passive: true });

                      window.visualViewport?.addEventListener?.('resize', () => {
                        applyIOSPlayerSizing();
                        scheduleIOSPlayerSizing(20);
                      }, { passive: true });

                      document.addEventListener('click', (event) => {
                        const target = event.target;
                        if (!target || !target.closest) {
                          return;
                        }

                        const fullscreenControl = target.closest([
                          '.bpx-player-ctrl-full',
                          '.bpx-player-ctrl-web',
                          '[class*="web-fullscreen"]',
                          '[class*="fullscreen"]'
                        ].join(','));
                        if (fullscreenControl) {
                          setIOSPlayerLayoutMode('expanded');
                          suppressIOSPlayerSizing(1400, 'expanded');
                        }

                        if (target.closest([
                          playerSelectors.playButton,
                          playerSelectors.danmakuToggle,
                          playerSelectors.subtitleToggle,
                          '.bpx-player-ctrl-full',
                          '.bpx-player-ctrl-web',
                          '[class*="playbackrate"]',
                          '[class*="speed"]'
                        ].join(','))) {
                          rememberActiveVideo(trackedVideo() || findPrimaryVideo());
                          scheduleIOSPlayerSizing(30);
                          scheduleIOSPlayerSizing(160);
                          scheduleSnapshot(60);
                          scheduleSnapshot(180);
                        }

                        if (target.closest('.video-pod')) {
                          scheduleVideoPodRefresh(40);
                          scheduleVideoPodRefresh(180);
                        }
                      }, true);

                      const observer = new MutationObserver(() => {
                        scheduleAutoplayRefresh(60);
                        scheduleIOSPlayerSizing(80);
                        scheduleSnapshot(120);
                        scheduleVideoPodRefresh(120);
                      });
                      observer.observe(document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ['class', 'aria-selected', 'aria-checked', 'aria-pressed', 'style']
                      });
                    }

                    disableAutoplayByDefault();
                    refreshVideoPods();
                    applyIOSPlayerSizing();
                    """,
                    settingKey: .playerMaskEnabled
                ),
            ]
        ),
    ]
}
