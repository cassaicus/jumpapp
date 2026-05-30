// Marks episode pages for the popup (optional future UI hooks).
(function () {
    if (!location.pathname.match(/^\/episode\/\d+/)) return;
    document.documentElement.dataset.jumpappEpisode = "1";
})();
