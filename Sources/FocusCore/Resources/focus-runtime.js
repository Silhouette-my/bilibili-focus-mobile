(() => {
  const incomingConfig = __FOCUS_CONFIG_JSON__;
  const incomingRules = __FOCUS_RULES_JSON__;
  const phase = "__FOCUS_PHASE__";
  const runtimeKey = "__FOCUS_RUNTIME__";
  const configKey = "__FOCUS_CONFIG__";
  const stylePrefix = "bili-focus-style-";
  const scriptStateKey = "__FOCUS_FEATURE_SCRIPT_STATE__";
  const runtimeVersion = "2026-06-24-runtime-trace-d-shared";

  function makeStyleId(ruleId, featureId) {
    return (stylePrefix + ruleId + "-" + featureId).replace(/[^a-zA-Z0-9_-]/g, "-");
  }

  function createRuntime() {
    const state = {
      runtimeVersion,
      currentPhase: phase,
      observerInstalled: false,
      historyInstalled: false,
      applyTimer: null,
      applyTimerToken: 0,
      applyTimerMetadata: null,
      lastApplyAt: 0,
      lastAppliedComparableURL: null,
      featureScriptState: window[scriptStateKey] || {}
    };

    function currentConfig() {
      return window[configKey] || {};
    }

    function postDebug(message, extra) {
      if (!currentConfig().debugMode) {
        return;
      }

      try {
        const debugSink = window.__FOCUS_DEBUG_SINK__;
        if (typeof debugSink === "function") {
          debugSink({
            message,
            extra: extra || null
          });
        }
      } catch (_) {}

      try {
        console.debug("[Focus]", message, extra || "");
      } catch (_) {}
    }

    function runtimeLabel(extra) {
      return Object.assign({
        runtimeVersion: state.runtimeVersion,
        phase: state.currentPhase
      }, extra || {});
    }

    function ensureStyle(styleId, css) {
      if (!css) {
        return;
      }

      let style = document.getElementById(styleId);
      if (!style) {
        style = document.createElement("style");
        style.id = styleId;
        (document.head || document.documentElement).appendChild(style);
      }

      if (style.textContent !== css) {
        style.textContent = css;
      }
    }

    function removeStyle(styleId) {
      const style = document.getElementById(styleId);
      if (style) {
        style.remove();
      }
    }

    function ensureViewport(content) {
      if (!content) {
        return;
      }

      let viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement("meta");
        viewport.name = "viewport";
        (document.head || document.documentElement).appendChild(viewport);
      }
      viewport.content = content;
    }

    function canonicalizeBilibiliURL(rawValue) {
      try {
        const url = new URL(rawValue, location.href);
        const host = (url.hostname || "").toLowerCase();
        const path = (url.pathname || "").toLowerCase();
        const isBilibiliHost = host === "www.bilibili.com" || host === "bilibili.com" || host === "m.bilibili.com";

        if (isBilibiliHost && (path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0)) {
          url.protocol = "https:";
          url.hostname = "www.bilibili.com";
          if (path.indexOf("/video/") === 0 && !url.pathname.endsWith("/")) {
            url.pathname = url.pathname + "/";
          }
          if (path.indexOf("/video/") === 0) {
            const preservedNames = new Set([
              "p",
              "t",
              "start_progress",
              "start_progress_ms",
              "spm_id_from",
              "from_spmid",
              "from_source"
            ]);
            Array.from(url.searchParams.keys()).forEach((key) => {
              if (!preservedNames.has(String(key).toLowerCase())) {
                url.searchParams.delete(key);
              }
            });
          }
        }

        return url.toString();
      } catch (_) {
        return rawValue;
      }
    }

    function comparableFocusURL(rawValue) {
      try {
        const url = new URL(rawValue, location.href);
        const host = (url.hostname || "").toLowerCase();
        const path = (url.pathname || "").toLowerCase();
        const isBilibiliHost = host === "www.bilibili.com" || host === "bilibili.com" || host === "m.bilibili.com";

        if (isBilibiliHost && (path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0)) {
          url.protocol = "https:";
          url.hostname = "www.bilibili.com";
          if (path.indexOf("/video/") === 0 && !url.pathname.endsWith("/")) {
            url.pathname = url.pathname + "/";
          }
          if (path.indexOf("/video/") === 0) {
            const preservedNames = new Set([
              "p",
              "t",
              "start_progress",
              "start_progress_ms",
              "spm_id_from",
              "from_spmid",
              "from_source"
            ]);
            Array.from(url.searchParams.keys()).forEach((key) => {
              if (!preservedNames.has(String(key).toLowerCase())) {
                url.searchParams.delete(key);
              }
            });
          }
        }

        return url.toString();
      } catch (_) {
        return rawValue;
      }
    }

    function normalizeHistoryURLArgument(rawValue) {
      if (rawValue == null || rawValue === "") {
        return rawValue;
      }

      const canonicalURL = comparableFocusURL(String(rawValue));
      return canonicalURL || rawValue;
    }

    function featureState(ruleId, featureId) {
      const key = ruleId + "::" + featureId;
      if (!state.featureScriptState[key]) {
        state.featureScriptState[key] = {};
      }
      window[scriptStateKey] = state.featureScriptState;
      return state.featureScriptState[key];
    }

    function runFeatureScript(rule, feature) {
      if (!feature.script) {
        return;
      }

      try {
        const executor = new Function("config", "helpers", feature.script);
        executor(currentConfig(), {
          canonicalizeBilibiliURL,
          featureState: featureState(rule.id, feature.featureId),
          postDebug,
        });
      } catch (error) {
        postDebug("featureScriptError", {
          ruleId: rule.id,
          featureId: feature.featureId,
          message: String(error && error.message ? error.message : error)
        });
      }
    }

    function matchesRule(rule) {
      const host = location.hostname;
      const path = location.pathname || "/";
      const hostMatch = !rule.hosts || rule.hosts.length === 0 || rule.hosts.indexOf(host) >= 0;
      const pathMatch = !rule.pathPrefixes || rule.pathPrefixes.length === 0 || rule.pathPrefixes.some((prefix) => path.indexOf(prefix) === 0);
      return hostMatch && pathMatch;
    }

    function isFeatureEnabled(feature) {
      const key = feature.settingKey;
      if (!key) {
        return true;
      }
      return !!currentConfig()[key];
    }

    function clearRule(rule) {
      (rule.features || []).forEach((feature) => removeStyle(makeStyleId(rule.id, feature.featureId)));
    }

    function applyRule(rule) {
      if (!matchesRule(rule)) {
        clearRule(rule);
        return;
      }

      if (rule.metaViewport) {
        ensureViewport(rule.metaViewport);
      }

      (rule.features || []).forEach((feature) => {
        const styleId = makeStyleId(rule.id, feature.featureId);
        if (isFeatureEnabled(feature)) {
          ensureStyle(styleId, feature.css);

          if (feature.css && document.getElementById(styleId)) {
            void document.body.offsetHeight;
          }

          runFeatureScript(rule, feature);
        } else {
          removeStyle(styleId);
        }
      });
    }

    function applyPhase(requestedPhase) {
      const applicableRules = (window.__FOCUS_RULES__ || []).filter((rule) => rule.runPhase === requestedPhase);
      applicableRules.forEach(applyRule);
      state.lastAppliedComparableURL = comparableFocusURL(location.href);
      postDebug("applyPhase", runtimeLabel({ requestedPhase }));
    }

    function applyAll() {
      applyPhase("documentStart");
      applyPhase("documentEnd");
    }

    function stableFocusVideoState() {
      const path = location.pathname || "/";
      const isVideoPage = path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0;
      const ready = isVideoPage && (
        document.documentElement.classList.contains("focus-native-video-ready")
        || document.body?.classList?.contains?.("focus-native-video-ready")
      );
      const renderableNativeAugment = ready && hasRenderableNativeVideoAugment();
      const visiblePrimaryVideo = ready && hasVisiblePrimaryVideo();

      return {
        isVideoPage,
        ready,
        renderableNativeAugment,
        visiblePrimaryVideo,
        stable: isVideoPage && ready && renderableNativeAugment && visiblePrimaryVideo
      };
    }

    function clearPendingApplyTimer() {
      state.applyTimerToken += 1;
      if (state.applyTimer !== null) {
        clearTimeout(state.applyTimer);
      }
      state.applyTimer = null;
      state.applyTimerMetadata = null;
    }

    function cancelPendingApply(cancelReason, extra) {
      if (state.applyTimer === null) {
        return false;
      }

      const pendingMetadata = state.applyTimerMetadata || {};
      clearPendingApplyTimer();
      postDebug("scheduleApply-cancelled", runtimeLabel(Object.assign({
        reason: pendingMetadata.reason || null,
        delay: pendingMetadata.delay,
        branch: "pending-cleared",
        cancelReason
      }, extra || {})));
      return true;
    }

    function scheduleApply(reason) {
      clearPendingApplyTimer();
      const now = Date.now();
      const stableState = stableFocusVideoState();
      const isVideoPage = stableState.isVideoPage;
      const isHistoryReason = reason === "pushState" || reason === "replaceState" || reason === "popstate" || reason === "hashchange";
      if (isVideoPage && isHistoryReason && comparableFocusURL(location.href) === state.lastAppliedComparableURL) {
        postDebug("scheduleApply-skipped", runtimeLabel({ reason, branch: "history-comparable" }));
        return;
      }
      const delay = isVideoPage ? 120 : Math.max(40, 80 - (now - state.lastApplyAt));

      if (delay === 0) {
        state.applyTimerToken += 1;
        state.lastApplyAt = Date.now();
        applyAll();
        postDebug("scheduleApply-immediate", runtimeLabel({ reason, delay, branch: "immediate" }));
      } else {
        const token = state.applyTimerToken + 1;
        state.applyTimerToken = token;
        state.applyTimerMetadata = {
          reason,
          delay,
          token
        };
        state.applyTimer = setTimeout(() => {
          if (token !== state.applyTimerToken) {
            postDebug("scheduleApply-cancelled", runtimeLabel({
              reason,
              delay,
              branch: "token-stale",
              cancelReason: "superseded",
              token,
              activeToken: state.applyTimerToken
            }));
            return;
          }

          state.applyTimer = null;
          state.applyTimerMetadata = null;
          const firedStableState = stableFocusVideoState();
          if (firedStableState.stable) {
            postDebug("scheduleApply-cancelled", runtimeLabel({
              reason,
              delay,
              branch: "stable-before-fire",
              cancelReason: "stable-before-fire",
              stableReady: firedStableState.ready ? 1 : 0,
              stableRenderable: firedStableState.renderableNativeAugment ? 1 : 0,
              stableVisibleVideo: firedStableState.visiblePrimaryVideo ? 1 : 0
            }));
            return;
          }

          state.lastApplyAt = Date.now();
          applyAll();
          postDebug("scheduleApply", runtimeLabel({ reason, delay, branch: "timer-fired" }));
        }, delay);
        postDebug("scheduleApply-queued", runtimeLabel({ reason, delay, branch: "timer-queued" }));
      }
    }

    function isIgnoredPlayerMutationTarget(node) {
      if (!node || !node.closest) {
        return false;
      }

      return !!node.closest([
        "#bilibili-player",
        "#playerWrap",
        ".player-wrap",
        ".bpx-player-container",
        ".bpx-player-video-wrap",
        ".bpx-player-video-area",
        ".bpx-player-row-dm-wrap",
        ".bpx-player-video-dm-wrap",
        ".bpx-player-dm-wrap",
        ".bilibili-player-video-danmaku"
      ].join(","));
    }

    function isFocusManagedNode(node) {
      if (!node) {
        return false;
      }

      const element = node.nodeType === 1 ? node : node.parentElement;
      if (!element) {
        return false;
      }

      const id = String(element.id || "");
      if (
        id === "focus-native-video-augment"
        || id === "focus-native-video-loading-mask"
        || id === "focus-native-opus-comments"
        || id === "focus-bootstrap-theme"
        || id.indexOf(stylePrefix) === 0
      ) {
        return true;
      }

      return !!element.closest([
        "#focus-native-video-augment",
        "#focus-native-video-loading-mask",
        "#focus-native-opus-comments"
      ].join(","));
    }

    function isSuppressedVideoAuxiliaryNode(node) {
      if (!node) {
        return false;
      }

      const element = node.nodeType === 1 ? node : node.parentElement;
      if (!element) {
        return false;
      }

      return !!element.closest([
        ".side-toolbar",
        ".right-entry",
        "[class*='side-toolbar']",
        "[class*='right-entry']"
      ].join(","));
    }

    function hasRenderableNativeVideoAugment() {
      const root = document.getElementById("focus-native-video-augment");
      if (!(root instanceof HTMLElement)) {
        return false;
      }

      const renderKey = root.getAttribute("data-focus-render-key");
      const version = root.getAttribute("data-focus-version");
      const isPlaceholder = root.hasAttribute("data-focus-placeholder");
      return !!renderKey && !!version && !isPlaceholder && root.children.length > 0;
    }

    function hasVisiblePrimaryVideo() {
      return Array.from(document.querySelectorAll("video")).some((node) => {
        if (!(node instanceof HTMLVideoElement)) {
          return false;
        }

        const rect = node.getBoundingClientRect();
        return rect.width > 120 && rect.height > 68;
      });
    }

    function hasVisiblePlayerLoadingOverlay() {
      return Array.from(document.querySelectorAll([
        "#bilibili-player [class*='loading']",
        "#playerWrap [class*='loading']",
        ".bpx-player-container [class*='loading']",
        "#bilibili-player [class*='skeleton']",
        "#playerWrap [class*='skeleton']",
        ".bpx-player-container [class*='skeleton']"
      ].join(","))).some((node) => {
        if (!(node instanceof HTMLElement)) {
          return false;
        }

        const rect = node.getBoundingClientRect();
        const style = window.getComputedStyle(node);
        return rect.width > 40
          && rect.height > 40
          && style.display !== "none"
          && style.visibility !== "hidden"
          && style.opacity !== "0";
      });
    }

    function isStableFocusVideoPage() {
      return stableFocusVideoState().stable;
    }

    function shouldScheduleForMutations(mutations) {
      if (!mutations || mutations.length === 0) {
        return false;
      }

      const path = location.pathname || "/";
      const isVideoPage = path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0;
      if (!isVideoPage) {
        return true;
      }

      if (hasVisiblePrimaryVideo() && hasVisiblePlayerLoadingOverlay()) {
        cancelPendingApply("player-loading-overlay-visible", {
          mutationCount: mutations.length,
          playerLoadingVisible: 1
        });
        postDebug("mutation-skip-player-loading", runtimeLabel({
          mutationCount: mutations.length,
          playerLoadingVisible: 1
        }));
        return false;
      }

      if (isStableFocusVideoPage()) {
        const currentStableState = stableFocusVideoState();
        cancelPendingApply("stable-mutation-skip", {
          mutationCount: mutations.length,
          stableReady: currentStableState.ready ? 1 : 0,
          stableRenderable: currentStableState.renderableNativeAugment ? 1 : 0,
          stableVisibleVideo: currentStableState.visiblePrimaryVideo ? 1 : 0
        });
        postDebug("mutation-skip-stable-video", runtimeLabel({
          mutationCount: mutations.length,
          stableReady: currentStableState.ready ? 1 : 0,
          stableRenderable: currentStableState.renderableNativeAugment ? 1 : 0,
          stableVisibleVideo: currentStableState.visiblePrimaryVideo ? 1 : 0
        }));
        return false;
      }

      return mutations.some((mutation) => {
        const target = mutation.target;
        const changedNodes = []
          .concat(Array.from(mutation.addedNodes || []))
          .concat(Array.from(mutation.removedNodes || []));

        if (changedNodes.length > 0 && changedNodes.every((node) => !node || node.nodeType !== 1 || isFocusManagedNode(node))) {
          return false;
        }

        if (target && target.nodeType === 1 && isFocusManagedNode(target)) {
          return false;
        }

        if (target && target.nodeType === 1 && isSuppressedVideoAuxiliaryNode(target)) {
          return false;
        }

        if (target && target.nodeType === 1 && !isIgnoredPlayerMutationTarget(target)) {
          return true;
        }

        return changedNodes.some((node) => {
          if (!node || node.nodeType !== 1) {
            return false;
          }

          if (isFocusManagedNode(node)) {
            return false;
          }

          if (isSuppressedVideoAuxiliaryNode(node)) {
            return false;
          }

          if (!isIgnoredPlayerMutationTarget(node)) {
            return true;
          }

          return !!node.querySelector?.([
            "#arc_toolbar_report",
            ".video-toolbar-container",
            ".video-pod",
            ".left-container",
            ".right-container"
          ].join(","));
        });
      });
    }

    function installHistoryHooks() {
      if (state.historyInstalled) {
        postDebug("installHistoryHooks-skipped", runtimeLabel({ reason: "already-installed" }));
        return;
      }

      state.historyInstalled = true;
      postDebug("installHistoryHooks", runtimeLabel());
      const wrap = (method) => {
        const original = history[method];
        history[method] = function () {
          const args = Array.from(arguments);
          if (args.length >= 3) {
            args[2] = normalizeHistoryURLArgument(args[2]);
          }
          const result = original.apply(this, args);
          scheduleApply(method);
          return result;
        };
      };

      wrap("pushState");
      wrap("replaceState");
      window.addEventListener("popstate", () => scheduleApply("popstate"));
      window.addEventListener("hashchange", () => scheduleApply("hashchange"));
    }

    function installObserver() {
      if (state.observerInstalled) {
        postDebug("installObserver-skipped", runtimeLabel({ reason: "already-installed" }));
        return;
      }

      state.observerInstalled = true;
      postDebug("installObserver", runtimeLabel());
      const observer = new MutationObserver((mutations) => {
        if (shouldScheduleForMutations(mutations)) {
          scheduleApply("mutation");
        }
      });
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true
      });
    }

    return {
      update(config, rules, currentPhase) {
        window[configKey] = config;
        window.__FOCUS_RULES__ = rules;
        if (currentPhase) {
          state.currentPhase = currentPhase;
        }
      },
      applyPhase,
      applyAll,
      cancelPendingApply,
      installHistoryHooks,
      installObserver
    };
  }

  const runtime = window[runtimeKey] || createRuntime();
  runtime.update(incomingConfig, incomingRules, phase);
  window[runtimeKey] = runtime;

  if (phase === "documentEnd") {
    runtime.installHistoryHooks();
    runtime.installObserver();
  }

  runtime.applyPhase(phase);
})();
