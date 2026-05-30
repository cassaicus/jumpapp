const statusEl = document.getElementById("status");
const titleEl = document.getElementById("episode-title");
const downloadBtn = document.getElementById("download");
const hintEl = document.getElementById("hint");

const EPISODE_PATH = /^\/episode\/\d+\/?$/;

function setStatus(text, { isError = false } = {}) {
    statusEl.textContent = text;
    statusEl.style.color = isError ? "#c00" : "";
}

function isEpisodeURL(url) {
    try {
        const parsed = new URL(url);
        return parsed.hostname === "tonarinoyj.jp" && EPISODE_PATH.test(parsed.pathname);
    } catch {
        return false;
    }
}

async function getActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs[0];
}

async function loadEpisodeInfo(url) {
    const jsonURL = url.replace(/\/$/, "") + ".json";
    const response = await fetch(jsonURL, {
        credentials: "include",
        headers: { Accept: "application/json" },
    });
    if (!response.ok) {
        throw new Error("話の情報を取得できませんでした");
    }
    const data = await response.json();
    const product = data.readableProduct;
    if (!product?.isPublic && !product?.hasPurchased) {
        throw new Error("この話は閲覧できません");
    }
    return {
        title: product.title,
        series: product.series?.title ?? "",
    };
}

async function init() {
    try {
        const tab = await getActiveTab();
        if (!tab?.url || !isEpisodeURL(tab.url)) {
            setStatus("話のページを開いてください");
            hintEl.hidden = false;
            return;
        }

        hintEl.hidden = true;
        downloadBtn.disabled = false;
        downloadBtn.dataset.url = tab.url;

        try {
            const info = await loadEpisodeInfo(tab.url);
            titleEl.hidden = false;
            titleEl.textContent = info.series
                ? `${info.series}\n${info.title}`
                : info.title;
            setStatus("この話をアプリに保存できます");
        } catch {
            titleEl.hidden = true;
            setStatus("この話をアプリに保存できます");
        }
    } catch (error) {
        setStatus(error.message ?? "エラーが発生しました", { isError: true });
    }
}

downloadBtn.addEventListener("click", async () => {
    const url = downloadBtn.dataset.url;
    if (!url) return;

    downloadBtn.disabled = true;
    setStatus("ダウンロード中…");

    try {
        const response = await browser.runtime.sendNativeMessage(
            "com.cassaicus.jumpapp",
            { action: "downloadEpisode", url }
        );

        if (!response?.ok) {
            throw new Error(response?.error ?? "保存に失敗しました");
        }

        const episode = response.episode;
        setStatus(`保存しました（${episode.pageCount}ページ）`);
        titleEl.hidden = false;
        titleEl.textContent = `${episode.seriesTitle}\n${episode.title}`;
    } catch (error) {
        setStatus(error.message ?? "保存に失敗しました", { isError: true });
        downloadBtn.disabled = false;
    }
});

init();
