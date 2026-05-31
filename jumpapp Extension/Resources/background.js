const NATIVE_APP = "com.cassaicus.jumpapp";

// Content scripts cannot call sendNativeMessage directly, so relay any
// native request through the background page.
const RELAYED_ACTIONS = new Set([
    "ping",
    "getEpisodeInfo",
    "getProcessedPage",
]);

browser.runtime.onMessage.addListener((request, _sender, sendResponse) => {
    // Backwards-compatible alias used by the popup ping test.
    const action = request?.action === "pingNative" ? "ping" : request?.action;

    if (!RELAYED_ACTIONS.has(action)) {
        return false;
    }

    const payload = { ...request, action };
    browser.runtime
        .sendNativeMessage(NATIVE_APP, payload)
        .then((response) => sendResponse(response))
        .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
});
