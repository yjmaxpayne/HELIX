(function () {
    "use strict";

    function projectBasePath() {
        var parts = window.location.pathname.split("/").filter(Boolean);
        var projectIndex = parts.indexOf("HELIX");
        if (projectIndex >= 0) {
            return "/" + parts.slice(0, projectIndex + 1).join("/") + "/";
        }
        return "/HELIX/";
    }

    function currentVersionName() {
        var parts = window.location.pathname.split("/").filter(Boolean);
        var projectIndex = parts.indexOf("HELIX");
        var version = projectIndex >= 0 ? parts[projectIndex + 1] : "";
        if (version === "latest" || /^v\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$/.test(version)) {
            return version;
        }
        return document.title.indexOf("latest (main)") >= 0 ? "latest" : "";
    }

    function fallbackLabel() {
        var pieces = document.title.split("\u00b7");
        if (pieces.length > 1) {
            return pieces.slice(1).join("\u00b7").trim();
        }
        return document.title || "documentation";
    }

    function normalizeVersions(data) {
        if (Array.isArray(data)) {
            return data;
        }
        if (data && Array.isArray(data.versions)) {
            return data.versions;
        }
        return [];
    }

    function findVersion(versions, name) {
        return versions.find(function (entry) {
            return entry.name === name;
        });
    }

    function latestRelease(versions) {
        return versions.find(function (entry) {
            return entry.name && entry.name !== "latest";
        });
    }

    function quickSwitchTarget(versions, current) {
        if (current === "latest") {
            return latestRelease(versions);
        }
        return findVersion(versions, "latest");
    }

    function quickSwitchText(target) {
        if (target.name === "latest") {
            return "View latest (main)";
        }
        return "View latest release: " + (target.label || target.name);
    }

    function renderSwitcher(versions) {
        var sidebarBrand = document.querySelector(".sidebar-brand");
        var sidebar = sidebarBrand || document.querySelector(".sidebar-drawer");
        if (!sidebar) {
            return;
        }

        var current = currentVersionName();
        var wrapper = document.createElement("div");
        wrapper.className = "helix-version-switcher";

        var label = document.createElement("label");
        label.className = "helix-version-switcher__label";
        label.htmlFor = "helix-version-select";
        label.textContent = "Docs";

        var select = document.createElement("select");
        select.id = "helix-version-select";
        select.className = "helix-version-switcher__select";
        select.setAttribute("aria-label", "Documentation version");

        if (versions.length === 0) {
            var option = document.createElement("option");
            option.textContent = fallbackLabel();
            option.selected = true;
            select.appendChild(option);
            select.disabled = true;
        } else {
            versions.forEach(function (entry) {
                var option = document.createElement("option");
                option.value = entry.path || entry.url || "";
                option.textContent = entry.label || entry.name || option.value;
                if (entry.name === current) {
                    option.selected = true;
                }
                select.appendChild(option);
            });
        }

        select.addEventListener("change", function () {
            if (select.value) {
                window.location.href = select.value;
            }
        });

        wrapper.appendChild(label);
        wrapper.appendChild(select);

        var quickTarget = quickSwitchTarget(versions, current);
        if (quickTarget && (quickTarget.path || quickTarget.url)) {
            var quickLink = document.createElement("a");
            quickLink.className = "helix-version-switcher__quick-link";
            quickLink.href = quickTarget.path || quickTarget.url;
            quickLink.textContent = quickSwitchText(quickTarget);
            wrapper.appendChild(quickLink);
        }

        if (sidebarBrand && sidebarBrand.parentNode) {
            sidebarBrand.parentNode.insertBefore(wrapper, sidebarBrand.nextSibling);
        } else {
            sidebar.insertBefore(wrapper, sidebar.firstChild);
        }
    }

    function loadVersions() {
        fetch(projectBasePath() + "versions.json", { cache: "no-store" })
            .then(function (response) {
                if (!response.ok) {
                    throw new Error("versions.json not found");
                }
                return response.json();
            })
            .then(function (data) {
                renderSwitcher(normalizeVersions(data));
            })
            .catch(function () {
                renderSwitcher([]);
            });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", loadVersions);
    } else {
        loadVersions();
    }
})();
