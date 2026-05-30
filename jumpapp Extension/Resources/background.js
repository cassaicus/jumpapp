browser.runtime.onMessage.addListener((request, _sender, sendResponse) => {
    if (request?.action === "pingNative") {
        return browser.runtime
            .sendNativeMessage("com.cassaicus.jumpapp", { action: "ping" })
            .then((response) => sendResponse(response))
            .catch((error) => sendResponse({ ok: false, error: String(error) }));
    }
    return false;
});
