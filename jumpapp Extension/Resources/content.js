// PoC: ask the host app for processed page images (page number drawn in the
// center) and swap them in place of the live GigaViewer page images in Safari.
(function () {
    const match = location.pathname.match(/^\/episode\/(\d+)/);
    if (!match) return;
    const episodeID = match[1];
    document.documentElement.dataset.jumpappEpisode = "1";

    const TAG = "[jumpapp]";
    const pageCache = new Map(); // pageIndex -> dataURL (or pending Promise)
    let pageCount = 0;
    let enabled = false;
    let observer = null;

    function send(message) {
        return browser.runtime.sendMessage(message);
    }

    function episodePageURL() {
        return location.origin + location.pathname.replace(/\/$/, "");
    }

    async function fetchProcessedPage(pageIndex) {
        if (pageCache.has(pageIndex)) return pageCache.get(pageIndex);
        const promise = send({ action: "getProcessedPage", episodeID, pageIndex })
            .then((res) => {
                if (!res?.ok) throw new Error(res?.error ?? "取得失敗");
                pageCache.set(pageIndex, res.dataURL);
                return res.dataURL;
            });
        pageCache.set(pageIndex, promise);
        return promise;
    }

    // GigaViewer keeps one <p> per page inside `.image-container`, always in
    // page order (positions[i] => page i), even though the reader virtualizes:
    // the actual <canvas>/<img> child is created/recycled as you scroll. The
    // <p> index is therefore the only stable source of truth for the page
    // number, so we bind numbers to that index, never to the image element.
    function getPageContainers() {
        const container = document.querySelector(".image-container");
        if (!container) return [];
        return [...container.getElementsByTagName("p")];
    }

    function pickImageElement(parent) {
        const el = parent.querySelector("canvas, img");
        if (!el) return null;
        const w = el.width || el.naturalWidth || el.clientWidth;
        const h = el.height || el.naturalHeight || el.clientHeight;
        return w >= 200 && h >= 200 ? el : null;
    }

    function paint(el, dataURL, pageIndex) {
        const img = new Image();
        img.onload = () => {
            if (el.tagName === "CANVAS") {
                const ctx = el.getContext("2d");
                if (!ctx) return;
                ctx.clearRect(0, 0, el.width, el.height);
                ctx.drawImage(img, 0, 0, el.width, el.height);
            } else {
                el.src = dataURL;
                el.srcset = "";
            }
            // Record which page index this element currently shows so a recycled
            // element (now under a different <p>) gets repainted with its number.
            el.dataset.jumpappPage = String(pageIndex);
        };
        img.src = dataURL;
    }

    async function applyAll() {
        if (!enabled) return;
        const containers = getPageContainers();
        let swapped = 0;
        for (let i = 0; i < containers.length; i++) {
            const el = pickImageElement(containers[i]);
            if (!el) continue;
            if (el.dataset.jumpappPage === String(i)) continue;
            try {
                const dataURL = await fetchProcessedPage(i);
                paint(el, dataURL, i);
                swapped += 1;
            } catch (error) {
                console.warn(TAG, "page", i, "failed:", error);
            }
        }
        console.log(TAG, `swapped ${swapped} page(s); ${containers.length} containers`);
    }

    let pending = null;
    function scheduleApply() {
        if (!enabled || pending) return;
        pending = setTimeout(() => {
            pending = null;
            applyAll();
        }, 200);
    }

    async function enable() {
        button.disabled = true;
        setStatus("確認中…");
        try {
            let info = await send({ action: "getEpisodeInfo", episodeID });
            if (!info?.ok) {
                setStatus(info?.error ?? "エラー", true);
                return;
            }

            if (!info.downloaded) {
                setStatus("アプリに保存中…");
                const dl = await send({
                    action: "downloadEpisode",
                    url: episodePageURL(),
                });
                if (!dl?.ok) {
                    setStatus(dl?.error ?? "保存に失敗しました", true);
                    return;
                }
                pageCount = dl.episode?.pageCount ?? 0;
            } else {
                pageCount = info.pageCount || 0;
            }

            enabled = true;
            setStatus(`差し替え中（${pageCount}ページ）`);
            updateButton();
            observer = new MutationObserver(scheduleApply);
            observer.observe(document.body, { childList: true, subtree: true });
            applyAll();
        } finally {
            button.disabled = false;
        }
    }

    function disable() {
        enabled = false;
        if (observer) observer.disconnect();
        observer = null;
        location.reload(); // simplest way to restore the original render
    }

    // --- Minimal verification UI -------------------------------------------
    const button = document.createElement("button");
    const statusEl = document.createElement("div");

    function updateButton() {
        button.textContent = enabled ? "元に戻す" : "翻訳画像に差し替え";
    }

    function setStatus(text, isError = false) {
        statusEl.textContent = text;
        statusEl.style.color = isError ? "#ffb4b4" : "#cfe9ff";
    }

    Object.assign(button.style, {
        position: "fixed", right: "12px", bottom: "60px", zIndex: "2147483647",
        padding: "10px 14px", borderRadius: "10px", border: "none",
        background: "#1d4ed8", color: "#fff", fontSize: "13px", fontWeight: "600",
        boxShadow: "0 2px 8px rgba(0,0,0,.3)",
    });
    Object.assign(statusEl.style, {
        position: "fixed", right: "12px", bottom: "108px", zIndex: "2147483647",
        padding: "4px 8px", borderRadius: "6px", background: "rgba(0,0,0,.7)",
        color: "#cfe9ff", fontSize: "11px", maxWidth: "60vw",
    });

    button.addEventListener("click", () => (enabled ? disable() : enable()));
    updateButton();

    function mountUI() {
        document.body.appendChild(statusEl);
        document.body.appendChild(button);
    }
    if (document.body) mountUI();
    else window.addEventListener("DOMContentLoaded", mountUI);
})();
