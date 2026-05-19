#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path
import html as html_lib

try:
    import select
except ImportError:  # Windows fallback
    select = None


BR = "\033[1;31m"
RS = "\033[0m"

# MARKMAP_FAVICON_URL = "https://markmap.js.org/favicon.png"
MARKMAP_FAVICON_URL = (
    "https://raw.githubusercontent.com/HelloWorldWinning/vps/main/icon/markmap_z7a.png"
)


DEFAULT_MAX_WIDTH = "380"
DEFAULT_COLOR_FREEZE_LEVEL = "3"
INITIAL_EXPAND_LEVEL = "2"

FILLER_INPUTS = {"", "n", "N", "呢", "你", "能"}


CSS_CODE = r"""

<style id="mm-custom-css">

/* Target the foreignObject directly */

#mindmap g[data-depth="1"] foreignObject {

  width: 130px !important;

}

/* Target the inner div */

#mindmap g[data-depth="1"] foreignObject div {

  width: 130px !important;

  max-width: 130px !important;

}


.mm-toolbar-brand {
  display: none !important;
}


</style>

"""

# Paste your generated/custom <script>...</script> here.
# Intentionally empty per request.
NEW_CODE = r"""<script>
(() => {
  function walk(node, fn, depth = 1) {
    if (!node) return;

    fn(node, depth);

    if (node.children) {
      node.children.forEach(child => walk(child, fn, depth + 1));
    }
  }

  function getMaxDepth(root) {
    let maxDepth = 1;

    walk(root, (_, depth) => {
      maxDepth = Math.max(maxDepth, depth);
    });

    return maxDepth;
  }

  function getVisibleDepth(node, depth = 1) {
    if (!node) return 1;

    let maxVisible = depth;

    if (!node.payload?.fold && node.children) {
      for (const child of node.children) {
        maxVisible = Math.max(maxVisible, getVisibleDepth(child, depth + 1));
      }
    }

    return maxVisible;
  }

  function setVisibleDepth(mm, visibleDepth) {
    const data = mm.state.data;
    const maxDepth = getMaxDepth(data);

    visibleDepth = Math.max(1, Math.min(visibleDepth, maxDepth));

    walk(data, (node, depth) => {
      if (!node.children || node.children.length === 0) return;

      node.payload = {
        ...node.payload,
        fold: depth >= visibleDepth ? 1 : 0
      };
    });

    mm.renderData(data);
  }

  function expandAll(mm) {
    const data = mm.state.data;

    walk(data, node => {
      if (!node.children || node.children.length === 0) return;

      node.payload = {
        ...node.payload,
        fold: 0
      };
    });

    mm.renderData(data);
  }

  function fit(mm) {
    mm.fit();
  }


  function hasChildren(node) {
    return Array.isArray(node?.children) && node.children.length > 0;
  }

  function setFold(node, fold) {
    if (!hasChildren(node)) return;

    node.payload = {
      ...node.payload,
      fold
    };
  }

  function getBoundMarkmapNode(el) {
    const bound = el?.__data__;

    if (!bound) return null;
    if (bound.data) return bound.data;

    return bound;
  }

  function getActiveNode() {
    // Primary source: node selected by Shift navigation.
    if (window.mmActiveNode) return window.mmActiveNode;

    // Fallback: currently highlighted Shift-navigation node, if still rendered.
    const activeEl = document.querySelector(".mm-shift-nav-hit");
    return getBoundMarkmapNode(activeEl);
  }

  function getMaxRelativeDepth(node, depth = 0) {
    if (!node) return 0;

    let maxDepth = depth;

    if (hasChildren(node)) {
      node.children.forEach(child => {
        maxDepth = Math.max(maxDepth, getMaxRelativeDepth(child, depth + 1));
      });
    }

    return maxDepth;
  }

  function getVisibleRelativeDepth(node, depth = 0) {
    if (!node) return 0;

    let maxVisible = depth;

    if (!node.payload?.fold && hasChildren(node)) {
      node.children.forEach(child => {
        maxVisible = Math.max(maxVisible, getVisibleRelativeDepth(child, depth + 1));
      });
    }

    return maxVisible;
  }

  function setActiveVisibleRelativeDepth(mm, activeNode, visibleDepth) {
    const maxDepth = getMaxRelativeDepth(activeNode);

    visibleDepth = Math.max(0, Math.min(visibleDepth, maxDepth));

    walk(activeNode, (node, depth) => {
      if (!hasChildren(node)) return;

      setFold(node, depth >= visibleDepth ? 1 : 0);
    }, 0);

    mm.renderData(mm.state.data);
  }

  function expandActiveNodeOneLevel(mm) {
    const activeNode = getActiveNode();

    if (!activeNode) {
      console.warn("No active node. Select one with Shift navigation first.");
      return false;
    }

    const currentDepth = getVisibleRelativeDepth(activeNode);
    const maxDepth = getMaxRelativeDepth(activeNode);

    setActiveVisibleRelativeDepth(
      mm,
      activeNode,
      Math.min(currentDepth + 1, maxDepth)
    );

    return true;
  }

  function collapseActiveNodeOneLevel(mm) {
    const activeNode = getActiveNode();

    if (!activeNode) {
      console.warn("No active node. Select one with Shift navigation first.");
      return false;
    }

    const currentDepth = getVisibleRelativeDepth(activeNode);

    setActiveVisibleRelativeDepth(
      mm,
      activeNode,
      Math.max(currentDepth - 1, 0)
    );

    return true;
  }


  function decodeHtml(value) {
    const textarea = document.createElement("textarea");
    textarea.innerHTML = String(value || "");
    return textarea.value;
  }

  function stripHtml(value) {
    const div = document.createElement("div");
    div.innerHTML = String(value || "");
    return div.textContent || div.innerText || "";
  }

  function normalizeText(value) {
    return stripHtml(decodeHtml(value))
      .normalize("NFKC")
      .replace(/[\u200B-\u200D\uFEFF]/g, "")
      .replace(/\u00A0/g, " ")
      .replace(/\s+/g, " ")
      .toLowerCase()
      .trim();
  }

  function normalizeTextCompact(value) {
    return normalizeText(value).replace(/\s+/g, "");
  }

  function getNodeText(node) {
    return [
      node.content,
      node.payload?.text,
      node.payload?.label,
      node.payload?.title
    ]
      .filter(Boolean)
      .map(normalizeText)
      .join(" ");
  }

  function textIncludes(text, keyword) {
    const source = normalizeText(text);
    const target = normalizeText(keyword);

    if (!target) return false;
    if (source.includes(target)) return true;

    return normalizeTextCompact(source).includes(normalizeTextCompact(target));
  }

  function findPaths(root, keyword) {
    const results = [];

    function dfs(node, path) {
      if (!node) return;

      const currentPath = [...path, node];
      const text = getNodeText(node);

      if (textIncludes(text, keyword)) {
        results.push(currentPath);
      }

      if (node.children) {
        node.children.forEach(child => dfs(child, currentPath));
      }
    }

    dfs(root, []);
    return results;
  }

  function clearFindHighlight() {
    document
      .querySelectorAll(".mm-find-box")
      .forEach(el => el.remove());

    document
      .querySelectorAll(".mm-find-hit")
      .forEach(el => el.classList.remove("mm-find-hit"));
  }

  function drawFindBoxes() {
    const SVG_NS = "http://www.w3.org/2000/svg";

    document.querySelectorAll(".mm-find-hit").forEach(el => {
      // Remove old box first so repeated redraws do not stack or overlap.
      el.querySelectorAll(".mm-find-box").forEach(box => box.remove());

      const target = el.querySelector("foreignObject, text");
      if (!target || typeof target.getBBox !== "function") return;

      let box;
      try {
        box = target.getBBox();
      } catch {
        return;
      }

      const padX = 5;
      const padY = 4;

      const rect = document.createElementNS(SVG_NS, "rect");
      rect.setAttribute("class", "mm-find-box");
      rect.setAttribute("x", box.x - padX);
      rect.setAttribute("y", box.y - padY);
      rect.setAttribute("width", box.width + padX * 2);
      rect.setAttribute("height", box.height + padY * 2);
      rect.setAttribute("rx", 6);
      rect.setAttribute("ry", 6);

      el.insertBefore(rect, el.firstChild);
    });
  }

  function highlightRenderedNodes(keyword) {
    clearFindHighlight();

    document.querySelectorAll(".markmap-node").forEach(el => {
      if (textIncludes(el.textContent, keyword)) {
        el.classList.add("mm-find-hit");
      }
    });

    drawFindBoxes();

    return document.querySelectorAll(".mm-find-hit").length;
  }

  function highlightRenderedNodesWhenReady(keyword) {
    let tries = 0;
    let foundCount = 0;
    const maxTries = 45;

    function retry() {
      const hits = highlightRenderedNodes(keyword);

      if (hits > 0) {
        foundCount += 1;
      }

      tries += 1;

      // Keep refreshing after first hit so boxes remain correct after expansion/layout animation.
      if (tries < maxTries && foundCount < 8) {
        setTimeout(() => requestAnimationFrame(retry), 80);
      }
    }

    requestAnimationFrame(retry);
  }

  function ensureFindStyle() {
    if (document.getElementById("mm-find-style")) return;

    const style = document.createElement("style");
    style.id = "mm-find-style";

    style.textContent = `
      .mm-find-hit text {
        fill: #000 !important;
        font-weight: 700;
      }

      .mm-find-hit circle {
        fill: #ff3d00 !important;
        stroke: #ffffff !important;
        stroke-width: 2px !important;
      }

      .mm-find-hit foreignObject {
        outline: none !important;
        box-shadow: none !important;
        background: transparent !important;
      }

      .mm-find-box {
        fill: rgba(255, 193, 7, 0.08);
        stroke: #ff3d00;
        stroke-width: 2.5px;
        vector-effect: non-scaling-stroke;
        filter: drop-shadow(0 0 5px rgba(255, 152, 0, 0.75));
        pointer-events: none;
        animation: mmFindBoxPulse 1s ease-in-out infinite alternate;
      }

      @keyframes mmFindBoxPulse {
        from {
          stroke-opacity: 0.75;
          filter: drop-shadow(0 0 3px rgba(255, 152, 0, 0.55));
        }
        to {
          stroke-opacity: 1;
          filter: drop-shadow(0 0 8px rgba(255, 61, 0, 0.85));
        }
      }
    `;

    document.head.appendChild(style);
  }

  function openMatchedPaths(matches) {
    matches.forEach(path => {
      path.slice(0, -1).forEach(node => {
        if (node.children && node.children.length > 0) {
          node.payload = {
            ...node.payload,
            fold: 0
          };
        }
      });
    });
  }

  function findInMap(mm) {
    const keyword = prompt("Find in map:");

    if (!keyword || !keyword.trim()) return;

    ensureFindStyle();

    const data = mm.state.data;
    const matches = findPaths(data, keyword);

    if (matches.length === 0) {
      clearFindHighlight();
      alert(`No match: ${keyword}`);
      return;
    }

    openMatchedPaths(matches);
    mm.renderData(data);

    highlightRenderedNodesWhenReady(keyword);

    setTimeout(() => {
      mm.fit();
    }, 200);
  }

  document.addEventListener("keydown", e => {
    const mm = window.mm;
    if (!mm || !mm.state?.data) return;

    const tag = e.target?.tagName?.toLowerCase();

    if (
      tag === "input" ||
      tag === "textarea" ||
      tag === "select" ||
      e.target?.isContentEditable
    ) {
      return;
    }

    const data = mm.state.data;
    const visibleDepth = getVisibleDepth(data);
    const maxDepth = getMaxDepth(data);

    if (e.key === " " || e.key === "0") {
      e.preventDefault();
      fit(mm);
      return;
    }

    if (e.key === "f" ||  e.key === "F")  {
      e.preventDefault();
      findInMap(mm);
      return;
    }

    if (e.key === "g" || e.key === "G" || e.key === "Enter") {
      e.preventDefault();
      expandAll(mm);
      setTimeout(() => fit(mm), 330);
      return;
    }

    // Uppercase D: expand 1 level for all nodes. Existing behavior.
    if (e.key === "D") {
      e.preventDefault();
      setVisibleDepth(mm, Math.min(visibleDepth + 1, maxDepth));
      setTimeout(() => fit(mm), 330);
      return;
    }

    // Lowercase d: expand 1 level only under current active node.
    if (e.key === "d") {
      e.preventDefault();

      if (expandActiveNodeOneLevel(mm)) {
        setTimeout(() => fit(mm), 330);
      }

      return;
    }

    // Uppercase S: collapse 1 level for all nodes. Existing behavior.
    if (e.key === "S") {
      e.preventDefault();
      setVisibleDepth(mm, Math.max(visibleDepth - 1, 1));
      setTimeout(() => fit(mm), 330);
      return;
    }

    // Lowercase s: collapse 1 level only under current active node.
    if (e.key === "s") {
      e.preventDefault();

      if (collapseActiveNodeOneLevel(mm)) {
        setTimeout(() => fit(mm), 330);
      }

      return;
    }






    if (e.key === "a" || e.key === "A"  ) {
      e.preventDefault();
      setVisibleDepth(mm, 1);
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (/^[1-9]$/.test(e.key)) {
      e.preventDefault();
      setVisibleDepth(mm, Number(e.key));
      setTimeout(() => fit(mm), 330);
      return;
    }

  });
})();
</script>

"""

NEW_CODE = (
    NEW_CODE
    + r"""
<script>
(() => {
  const MAX_SEQUENCE_LENGTH = 32;
  const RENDER_SETTLE_MS = 360;

// 1 = original HUD time.
// 0.5 = show for half time.
const HUD_TIMEOUT_RATIO = 0.5;

  // Zoom tuning.
  // Zoom window = selected node + rendered descendants within requested expanded levels.
  const FOCUS_ZOOM_DURATION_MS = 320;
  const FOCUS_MIN_SCALE = 0.12;
  const FOCUS_MAX_SCALE = 2.25;
  const FOCUS_PADDING_X = 180;
  const FOCUS_PADDING_Y = 120;

// d = expand: move view left.
// s = collapse: move view slightly right.
// const FOCUS_OFFSET_X_EXPAND = -250;
const FOCUS_OFFSET_X_EXPAND = -550;
const FOCUS_OFFSET_X_COLLAPSE = 60;

// Current offset used by zoomToExpandedMapWindow().
let focusOffsetX = FOCUS_OFFSET_X_EXPAND;

  let shiftNavActive = false;
  let shiftNavBuffer = "";
  let hudTimer = null;

  // Current active node shared by:
  // 1. shift-number navigation
  // 2. manual mouse click
  // 3. s / d expand-shrink hotkeys
  let activeSelection = null;

  function isEditableTarget(target) {
    const tag = target?.tagName?.toLowerCase();

    return (
      tag === "input" ||
      tag === "textarea" ||
      tag === "select" ||
      target?.isContentEditable
    );
  }

  function getDigitFromEvent(e) {
    const code = e.code || "";
    const match = code.match(/^(Digit|Numpad)(\d)$/);

    if (match) return match[2];
    if (/^\d$/.test(e.key || "")) return e.key;

    return "";
  }

  function getSeparatorFromEvent(e) {
    if (e.key === "~") return "~";
    if (e.shiftKey && e.code === "Backquote") return "~";
    return "";
  }

  function getNavCharFromEvent(e) {
    return getDigitFromEvent(e) || getSeparatorFromEvent(e);
  }

  function walk(node, fn, depth = 1, path = []) {
    if (!node) return;

    const currentPath = [...path, node];
    fn(node, depth, currentPath);

    if (Array.isArray(node.children)) {
      node.children.forEach(child => walk(child, fn, depth + 1, currentPath));
    }
  }

  function hasChildren(node) {
    return Array.isArray(node?.children) && node.children.length > 0;
  }

  function setFold(node, fold) {
    if (!hasChildren(node)) return;

    node.payload = {
      ...node.payload,
      fold
    };
  }

  function collapseAll(root) {
    walk(root, node => {
      if (hasChildren(node)) setFold(node, 1);
    });
  }

  function collectNodesAtDepth(root, targetDepth) {
    const results = [];

    walk(root, (node, depth, path) => {
      if (depth === targetDepth) {
        results.push({ node, path });
      }
    });

    return results;
  }

  function openPathToTarget(path) {
    path.slice(0, -1).forEach(node => {
      if (hasChildren(node)) setFold(node, 0);
    });
  }

  function expandTargetByLevels(target, extraLevels) {
    extraLevels = Math.max(0, Number(extraLevels) || 0);

    if (!hasChildren(target)) return;

    if (extraLevels === 0) {
      setFold(target, 1);
      return;
    }

    function expand(node, relativeDepth) {
      if (!hasChildren(node)) return;

      if (relativeDepth < extraLevels) {
        setFold(node, 0);

        node.children.forEach(child => {
          expand(child, relativeDepth + 1);
        });
      } else {
        setFold(node, 1);
      }
    }

    expand(target, 0);
  }

  function collectExpandedWindowNodes(targetNode, extraLevels) {
    const nodes = [];
    const maxRelativeDepth = Math.max(0, Number(extraLevels) || 0);

    function collect(node, relativeDepth) {
      if (!node) return;

      nodes.push(node);

      if (relativeDepth >= maxRelativeDepth) return;

      if (Array.isArray(node.children)) {
        node.children.forEach(child => {
          collect(child, relativeDepth + 1);
        });
      }
    }

    collect(targetNode, 0);
    return nodes;
  }

function decodeHtmlEntities(value) {
  const textarea = document.createElement("textarea");
  textarea.innerHTML = String(value ?? "");
  return textarea.value;
}

function htmlToPlainText(value) {
  const div = document.createElement("div");

  // First decode entities like &#x7B80;, then strip real HTML tags.
  div.innerHTML = decodeHtmlEntities(value);

  return div.textContent || div.innerText || "";
}

function cleanHudText(value) {
  return htmlToPlainText(value)
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\u00A0/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function getNodeText(node) {
  return [
    node?.content,
    node?.payload?.text,
    node?.payload?.label,
    node?.payload?.title
  ]
    .filter(value => value !== undefined && value !== null && String(value) !== "")
    .map(cleanHudText)
    .filter(Boolean)
    .join(" ");
}



  function isPositiveInteger(value) {
    return Number.isInteger(value) && value >= 1;
  }

  function isNonNegativeInteger(value) {
    return Number.isInteger(value) && value >= 0;
  }

  /*
    Compact mode:
      AB      = level A, item B
      ABZ     = level A, item B, expand Z levels

    Example:
      234     = level 2, item 3, expand next 4 levels

    Separator mode:
      X~Y     = level X, item Y
      X~Y~Z   = level X, item Y, expand Z levels
  */
  function parseCompactSequence(sequence) {
    if (!/^\d{2,3}$/.test(sequence)) return null;

    const targetDepth = Number(sequence[0]);
    const itemIndex = Number(sequence[1]);
    const extraLevels = sequence.length === 3 ? Number(sequence[2]) : 0;

    if (!isPositiveInteger(targetDepth)) return null;
    if (!isPositiveInteger(itemIndex)) return null;
    if (!isNonNegativeInteger(extraLevels)) return null;

    return {
      mode: "Compact",
      targetDepth,
      itemIndex,
      extraLevels
    };
  }

  function parseSeparatorSequence(sequence) {
    if (!/^\d+~\d+(?:~\d+)?$/.test(sequence)) return null;

    const parts = sequence.split("~");

    const targetDepth = Number(parts[0]);
    const itemIndex = Number(parts[1]);
    const extraLevels = parts.length === 3 ? Number(parts[2]) : 0;

    if (!isPositiveInteger(targetDepth)) return null;
    if (!isPositiveInteger(itemIndex)) return null;
    if (!isNonNegativeInteger(extraLevels)) return null;

    return {
      mode: "Separator",
      targetDepth,
      itemIndex,
      extraLevels
    };
  }

  function parseShiftSequence(sequence) {
    if (sequence.includes("~")) {
      return parseSeparatorSequence(sequence);
    }

    return parseCompactSequence(sequence);
  }

  function ensureNavStyle() {
    if (document.getElementById("mm-shift-nav-style")) return;

    const style = document.createElement("style");
    style.id = "mm-shift-nav-style";

    style.textContent = `
      .mm-shift-nav-hit text {
        fill: #000 !important;
        font-weight: 800 !important;
      }

      .mm-shift-nav-hit circle {
        fill: #2962ff !important;
        stroke: #ffffff !important;
        stroke-width: 2.5px !important;
      }

      .mm-shift-nav-box {
        fill: rgba(41, 98, 255, 0.03);
        stroke: #2962ff;
        stroke-width: 2.5px;
        vector-effect: non-scaling-stroke;
        pointer-events: none;
        filter: drop-shadow(0 0 6px rgba(41, 98, 255, 0.6));
      }

      #mm-shift-nav-hud {
        position: fixed;
        right: 14px;
        bottom: 14px;
        z-index: 999999;
        padding: 8px 11px;
        border-radius: 10px;
        background: rgba(20, 20, 20, 0.82);
        color: #fff;
        font: 600 13px/1.35 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: 0.02em;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.22);
        user-select: none;
        pointer-events: none;
      }
    `;

    document.head.appendChild(style);
  }


function showHud(message, timeout = 900) {
  ensureNavStyle();

  let hud = document.getElementById("mm-shift-nav-hud");

  if (!hud) {
    hud = document.createElement("div");
    hud.id = "mm-shift-nav-hud";
    document.body.appendChild(hud);
  }

  // Safety layer: decode even if caller passed an encoded string directly.
  hud.textContent = cleanHudText(message);

  clearTimeout(hudTimer);

  if (timeout > 0) {
    const adjustedTimeout = Math.max(1, Math.round(timeout * HUD_TIMEOUT_RATIO));

    hudTimer = setTimeout(() => {
      hud.remove();
    }, adjustedTimeout);
  }
}



  function showSequenceHud(sequence) {
    if (sequence.includes("~")) {
      const parts = sequence.split("~");
      const level = parts[0] || "?";
      const item = parts[1] || "…";
      const expand = parts[2];

      if (parts.length >= 3) {
        showHud(`Separator: level ${level}, item ${item}, expand +${expand || "…"}`, 0);
      } else if (sequence.endsWith("~")) {
        showHud(`Separator: level ${level}, item …`, 0);
      } else {
        showHud(`Separator: level ${level}, item ${item}`, 0);
      }

      return;
    }

    if (sequence.length === 1) {
      showHud(`Compact: level ${sequence}`, 0);
    } else if (sequence.length === 2) {
      showHud(`Compact: level ${sequence[0]}, item ${sequence[1]}`, 0);
    } else if (sequence.length === 3) {
      showHud(`Compact: level ${sequence[0]}, item ${sequence[1]}, expand +${sequence[2]}`, 0);
    } else {
      showHud("Compact supports AB or ABZ. Use X~Y or X~Y~Z for larger numbers.", 0);
    }
  }

  function clearNavHighlight() {
    document
      .querySelectorAll(".mm-shift-nav-box, .mm-shift-nav-scope-box")
      .forEach(el => el.remove());

    document
      .querySelectorAll(".mm-shift-nav-hit")
      .forEach(el => el.classList.remove("mm-shift-nav-hit"));
  }

  function getBoundMarkmapNode(el) {
    const bound = el?.__data__;

    if (!bound) return null;
    if (bound.data) return bound.data;

    return bound;
  }

  function sameNode(a, b) {
    if (!a || !b) return false;
    if (a === b) return true;

    if (a.state?.id && b.state?.id && a.state.id === b.state.id) return true;
    if (a.id && b.id && a.id === b.id) return true;

    return false;
  }

  function isNodeInList(node, list) {
    return list.some(item => sameNode(node, item));
  }

  function findRenderedNodeElement(targetNode) {
    const renderedNodes = document.querySelectorAll(".markmap-node");

    for (const el of renderedNodes) {
      const boundNode = getBoundMarkmapNode(el);

      if (sameNode(boundNode, targetNode)) {
        return el;
      }
    }

    return null;
  }

  function findRenderedWindowElements(windowNodes) {
    const results = [];
    const renderedNodes = document.querySelectorAll(".markmap-node");

    for (const el of renderedNodes) {
      const boundNode = getBoundMarkmapNode(el);

      if (isNodeInList(boundNode, windowNodes)) {
        results.push(el);
      }
    }

    return results;
  }



function getVisibleExtraLevels(node) {
  let maxVisibleExtraLevels = 0;

  function visit(current, relativeDepth) {
    if (!current || !hasChildren(current)) return;

    // If current node is folded, descendants are not visible.
    if (current.payload?.fold) return;

    current.children.forEach(child => {
      const childRelativeDepth = relativeDepth + 1;

      maxVisibleExtraLevels = Math.max(
        maxVisibleExtraLevels,
        childRelativeDepth
      );

      visit(child, childRelativeDepth);
    });
  }

  visit(node, 0);

  return maxVisibleExtraLevels;
}


function snapshotSubtreeFolds(root) {
  const snapshot = [];

  walk(root, node => {
    if (!hasChildren(node)) return;

    snapshot.push({
      node,
      fold: node.payload?.fold ? 1 : 0
    });
  });

  return snapshot;
}

function restoreSubtreeFolds(snapshot) {
  if (!Array.isArray(snapshot)) return;

  snapshot.forEach(item => {
    if (!item?.node || !hasChildren(item.node)) return;

    item.node.payload = {
      ...item.node.payload,
      fold: item.fold ? 1 : 0
    };
  });
}

function forEachVisibleNode(root, fn, relativeDepth = 0) {
  if (!root) return;

  fn(root, relativeDepth);

  if (!hasChildren(root)) return;
  if (root.payload?.fold) return;

  root.children.forEach(child => {
    forEachVisibleNode(child, fn, relativeDepth + 1);
  });
}

function collapseOneVisibleLevel(root) {
  const maxVisibleExtraLevels = getVisibleExtraLevels(root);

  if (maxVisibleExtraLevels <= 0) {
    return 0;
  }

  if (maxVisibleExtraLevels === 1) {
    setFold(root, 1);
    return getVisibleExtraLevels(root);
  }

  const parentDepthToCollapse = maxVisibleExtraLevels - 1;

  forEachVisibleNode(root, (node, relativeDepth) => {
    if (relativeDepth !== parentDepthToCollapse) return;
    if (!hasChildren(node)) return;

    setFold(node, 1);
  });

  return getVisibleExtraLevels(root);
}

function expandOneVisibleLevel(root) {
  const maxVisibleExtraLevels = getVisibleExtraLevels(root);
  const candidates = [];

  forEachVisibleNode(root, (node, relativeDepth) => {
    if (relativeDepth !== maxVisibleExtraLevels) return;
    if (!hasChildren(node)) return;
    if (!node.payload?.fold) return;

    candidates.push(node);
  });

  candidates.forEach(node => {
    setFold(node, 0);
  });

  return getVisibleExtraLevels(root);
}



function setActiveSelection(
  node,
  path,
  extraLevels = 0,
  mode = "uniform",
  foldSnapshot = null
) {
  if (!node || !Array.isArray(path) || !path.length) return false;

  activeSelection = {
    node,
    path,
    extraLevels: Math.max(0, Number(extraLevels) || 0),
    mode,
    foldSnapshot
  };

  return true;
}




  function findNodePath(root, targetNode) {
    let foundPath = null;

    walk(root, (node, _depth, path) => {
      if (foundPath) return;

      if (sameNode(node, targetNode)) {
        foundPath = path;
      }
    });

    return foundPath;
  }

  function getClickedMarkmapNodeElement(target) {
    return target?.closest?.(".markmap-node") || null;
  }











function setActiveSelectionFromRenderedElement(
  el,
  previousVisibleExtraLevels = null,
  previousFoldSnapshot = null
) {
  const mm = window.mm;
  if (!mm || !mm.state?.data || !el) return false;

  const clickedNode = getBoundMarkmapNode(el);
  if (!clickedNode) return false;

  const path = findNodePath(mm.state.data, clickedNode);
  if (!path) return false;

  const node = path[path.length - 1];

  const currentVisibleExtraLevels = getVisibleExtraLevels(node);
  const currentFoldSnapshot = snapshotSubtreeFolds(node);

  const beforeExtraLevels = Number(previousVisibleExtraLevels) || 0;

  const usePreviousShape = beforeExtraLevels > currentVisibleExtraLevels;

  const extraLevels = usePreviousShape
    ? beforeExtraLevels
    : currentVisibleExtraLevels;

  const foldSnapshot = usePreviousShape
    ? previousFoldSnapshot
    : currentFoldSnapshot;

  setActiveSelection(
    node,
    path,
    extraLevels,
    "preserve",
    foldSnapshot
  );

  clearNavHighlight();

  const currentEl = findRenderedNodeElement(node) || el;

  if (currentEl) {
    currentEl.classList.add("mm-shift-nav-hit");
    drawTargetBox(currentEl);
  }

  const label = getNodeText(node) || "clicked node";
  showHud(`Active +${extraLevels}: ${label}`, 900);

  return true;
}



function renderActiveSelection(mm) {
  if (!mm || !mm.state?.data || !activeSelection?.node || !activeSelection?.path) {
    showHud("No active node. Shift-select or click a node first.");
    return;
  }

  function afterRender() {
    setTimeout(() => {
      const visibleExtraLevels = getVisibleExtraLevels(activeSelection.node);

      activeSelection.extraLevels = visibleExtraLevels;
      activeSelection.foldSnapshot = snapshotSubtreeFolds(activeSelection.node);

      focusExpandedMapWhenReady(
        mm,
        activeSelection.node,
        visibleExtraLevels
      );

      const label = getNodeText(activeSelection.node) || "active node";
      showHud(`Active +${visibleExtraLevels}: ${label}`, 900);
    }, RENDER_SETTLE_MS);
  }

  try {
    const result = mm.renderData(mm.state.data);

    if (result && typeof result.then === "function") {
      result.then(afterRender).catch(afterRender);
    } else {
      afterRender();
    }
  } catch {
    showHud("Render failed");
  }
}





function adjustActiveSelectionLevels(delta) {
  const mm = window.mm;

  if (!mm || !mm.state?.data) return;

  // d passes delta > 0, s passes delta < 0.
  focusOffsetX = delta > 0
    ? FOCUS_OFFSET_X_EXPAND
    : FOCUS_OFFSET_X_COLLAPSE;


  if (!activeSelection?.node || !activeSelection?.path) {
    showHud("No active node. Shift-select or click a node first.");
    return;
  }

  if (activeSelection.mode === "preserve") {
    restoreSubtreeFolds(activeSelection.foldSnapshot);

    if (delta > 0) {
      activeSelection.extraLevels = expandOneVisibleLevel(activeSelection.node);
    } else {
      activeSelection.extraLevels = collapseOneVisibleLevel(activeSelection.node);
    }

    activeSelection.foldSnapshot = snapshotSubtreeFolds(activeSelection.node);

    renderActiveSelection(mm);
    return;
  }

  activeSelection.extraLevels = Math.max(
    0,
    activeSelection.extraLevels + delta
  );

  collapseAll(mm.state.data);
  openPathToTarget(activeSelection.path);
  expandTargetByLevels(activeSelection.node, activeSelection.extraLevels);

  renderActiveSelection(mm);
}



  function drawTargetBox(el) {
    const SVG_NS = "http://www.w3.org/2000/svg";

    if (!el) return;

    el.querySelectorAll(".mm-shift-nav-box").forEach(box => box.remove());

    const target = el.querySelector("foreignObject, text");
    if (!target || typeof target.getBBox !== "function") return;

    let box;

    try {
      box = target.getBBox();
    } catch {
      return;
    }

    const padX = 7;
    const padY = 5;

    const rect = document.createElementNS(SVG_NS, "rect");
    rect.setAttribute("class", "mm-shift-nav-box");
    rect.setAttribute("x", box.x - padX);
    rect.setAttribute("y", box.y - padY);
    rect.setAttribute("width", box.width + padX * 2);
    rect.setAttribute("height", box.height + padY * 2);
    rect.setAttribute("rx", 7);
    rect.setAttribute("ry", 7);

    el.insertBefore(rect, el.firstChild);
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function getD3Node(value) {
    if (!value) return null;
    if (typeof value.node === "function") return value.node();
    return value;
  }

  function getSvgNode(mm, fallbackEl) {
    return (
      getD3Node(mm?.svg) ||
      fallbackEl?.ownerSVGElement ||
      document.querySelector("svg.markmap, svg")
    );
  }

  function getZoomLayerNode(mm, svgNode, fallbackEl) {
    const direct = getD3Node(mm?.g);
    if (direct) return direct;

    let node = fallbackEl;
    let topmostGroup = null;

    while (node && node !== svgNode) {
      if (node.tagName?.toLowerCase() === "g") {
        topmostGroup = node;
      }

      node = node.parentNode;
    }

    return topmostGroup || svgNode?.querySelector("g");
  }

  function getSvgViewportSize(svgNode) {
    const rect = svgNode.getBoundingClientRect?.();
    const viewBox = svgNode.viewBox?.baseVal;

    const width =
      rect?.width ||
      viewBox?.width ||
      Number(svgNode.getAttribute("width")) ||
      window.innerWidth ||
      800;

    const height =
      rect?.height ||
      viewBox?.height ||
      Number(svgNode.getAttribute("height")) ||
      window.innerHeight ||
      600;

    return { width, height };
  }

  function getElementBoxInZoomLayerCoords(targetEl, zoomLayerNode) {
    const svgNode = targetEl.ownerSVGElement;
    const rect = targetEl.getBoundingClientRect?.();

    if (!svgNode || !rect || rect.width <= 0 || rect.height <= 0) {
      if (typeof targetEl.getBBox === "function") {
        const box = targetEl.getBBox();

        return {
          x: box.x,
          y: box.y,
          width: box.width,
          height: box.height
        };
      }

      return null;
    }

    const ctm = zoomLayerNode.getScreenCTM?.();
    if (!ctm) return null;

    const inverse = ctm.inverse();
    const point = svgNode.createSVGPoint();

    function convert(x, y) {
      point.x = x;
      point.y = y;

      const converted = point.matrixTransform(inverse);

      return {
        x: converted.x,
        y: converted.y
      };
    }

    const p1 = convert(rect.left, rect.top);
    const p2 = convert(rect.right, rect.top);
    const p3 = convert(rect.right, rect.bottom);
    const p4 = convert(rect.left, rect.bottom);

    const xs = [p1.x, p2.x, p3.x, p4.x];
    const ys = [p1.y, p2.y, p3.y, p4.y];

    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    };
  }

  function unionBoxes(boxes) {
    const validBoxes = boxes.filter(box => {
      return (
        box &&
        Number.isFinite(box.x) &&
        Number.isFinite(box.y) &&
        Number.isFinite(box.width) &&
        Number.isFinite(box.height) &&
        box.width > 0 &&
        box.height > 0
      );
    });

    if (!validBoxes.length) return null;

    const minX = Math.min(...validBoxes.map(box => box.x));
    const minY = Math.min(...validBoxes.map(box => box.y));
    const maxX = Math.max(...validBoxes.map(box => box.x + box.width));
    const maxY = Math.max(...validBoxes.map(box => box.y + box.height));

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    };
  }

  function createZoomTransform(x, y, k) {
    const d3ZoomIdentity =
      window.d3?.zoomIdentity ||
      window.markmap?.d3?.zoomIdentity;

    if (d3ZoomIdentity) {
      return d3ZoomIdentity.translate(x, y).scale(k);
    }

    return {
      x,
      y,
      k,
      toString() {
        return `translate(${this.x},${this.y}) scale(${this.k})`;
      }
    };
  }

  function applyZoomTransform(mm, svgNode, zoomLayerNode, transform) {
    if (mm?.svg && mm?.zoom && typeof mm.svg.call === "function" && transform?.k) {
      try {
        if (typeof mm.svg.transition === "function") {
          mm.svg
            .transition()
            .duration(FOCUS_ZOOM_DURATION_MS)
            .call(mm.zoom.transform, transform);
        } else {
          mm.svg.call(mm.zoom.transform, transform);
        }

        return true;
      } catch {
        // Fallback below.
      }
    }

    if (zoomLayerNode && transform?.toString) {
      zoomLayerNode.setAttribute("transform", transform.toString());
      svgNode.__zoom = transform;
      return true;
    }

    return false;
  }

  function getRenderedContentBox(el, zoomLayerNode) {
    const contentEl = el.querySelector("foreignObject, text") || el;
    return getElementBoxInZoomLayerCoords(contentEl, zoomLayerNode);
  }

  function zoomToExpandedMapWindow(mm, windowElements, targetElement) {
    if (!windowElements.length && targetElement) {
      windowElements = [targetElement];
    }

    if (!windowElements.length) return false;

    const firstEl = windowElements[0];
    const svgNode = getSvgNode(mm, firstEl);
    if (!svgNode) return false;

    const zoomLayerNode = getZoomLayerNode(mm, svgNode, firstEl);
    if (!zoomLayerNode) return false;

    const boxes = windowElements.map(el => {
      return getRenderedContentBox(el, zoomLayerNode);
    });

    const zoomWindow = unionBoxes(boxes);
    if (!zoomWindow) return false;

    const viewport = getSvgViewportSize(svgNode);

    const padX = Math.min(FOCUS_PADDING_X, viewport.width * 0.28);
    const padY = Math.min(FOCUS_PADDING_Y, viewport.height * 0.28);

    const availableWidth = Math.max(80, viewport.width - padX * 2);
    const availableHeight = Math.max(80, viewport.height - padY * 2);

    const rawScale = Math.min(
      availableWidth / zoomWindow.width,
      availableHeight / zoomWindow.height
    );

    const scale = clamp(rawScale, FOCUS_MIN_SCALE, FOCUS_MAX_SCALE);

    const centerX = zoomWindow.x + zoomWindow.width / 2;
    const centerY = zoomWindow.y + zoomWindow.height / 2;

    const translateX = viewport.width / 2 - centerX * scale + focusOffsetX;
    const translateY = viewport.height / 2 - centerY * scale;

    const transform = createZoomTransform(translateX, translateY, scale);

    return applyZoomTransform(mm, svgNode, zoomLayerNode, transform);
  }

  function focusExpandedMapWhenReady(mm, targetNode, extraLevels) {
    let tries = 0;
    const maxTries = 30;

    function retry() {
      clearNavHighlight();

      const targetEl = findRenderedNodeElement(targetNode);

      if (targetEl) {
        const windowNodes = collectExpandedWindowNodes(targetNode, extraLevels);
        const windowElements = findRenderedWindowElements(windowNodes);

        targetEl.classList.add("mm-shift-nav-hit");
        drawTargetBox(targetEl);

        requestAnimationFrame(() => {
          zoomToExpandedMapWindow(mm, windowElements, targetEl);
        });

        return;
      }

      tries += 1;

      if (tries < maxTries) {
        setTimeout(() => requestAnimationFrame(retry), 70);
      } else {
        showHud("Target not rendered");
      }
    }

    requestAnimationFrame(retry);
  }

  function executeShiftNavigation(sequence) {
    const mm = window.mm;

    if (!mm || !mm.state?.data) {
      showHud("No markmap instance found");
      return;
    }

    const parsed = parseShiftSequence(sequence);

    if (!parsed) {
      showHud(`Invalid nav: ${sequence}`);
      return;
    }

    const { mode, targetDepth, itemIndex, extraLevels } = parsed;
    const data = mm.state.data;
    const nodesAtDepth = collectNodesAtDepth(data, targetDepth);
    const selected = nodesAtDepth[itemIndex - 1];

    if (!selected) {
      showHud(`No item: level ${targetDepth}, #${itemIndex}`);
      return;
    }

    // Important:
    // Shift navigation now also updates the shared current active node.
    setActiveSelection(
  selected.node,
  selected.path,
  extraLevels,
  "uniform",
  null
);

    collapseAll(data);
    openPathToTarget(selected.path);
    expandTargetByLevels(selected.node, extraLevels);

    const label = getNodeText(selected.node) || `level ${targetDepth} #${itemIndex}`;

    function afterRender() {
      setTimeout(() => {
        focusExpandedMapWhenReady(mm, selected.node, extraLevels);

        if (extraLevels > 0) {
          showHud(`${mode}: L${targetDepth} #${itemIndex} +${extraLevels}: ${label}`, 1300);
        } else {
          showHud(`${mode}: L${targetDepth} #${itemIndex}: ${label}`, 1300);
        }
      }, RENDER_SETTLE_MS);
    }

    try {
      const result = mm.renderData(data);

      if (result && typeof result.then === "function") {
        result.then(afterRender).catch(afterRender);
      } else {
        afterRender();
      }
    } catch {
      showHud("Render failed");
    }
  }

  // Manual mouse click now becomes the current active node.


document.addEventListener(
  "click",
  e => {
    if (isEditableTarget(e.target)) return;

    const el = getClickedMarkmapNodeElement(e.target);
    if (!el) return;

    const mm = window.mm;
    if (!mm || !mm.state?.data) return;

    const clickedNode = getBoundMarkmapNode(el);
    if (!clickedNode) return;

    const path = findNodePath(mm.state.data, clickedNode);
    if (!path) return;

    const node = path[path.length - 1];

    // Capture the exact visible shape before Markmap's own click behavior
    // possibly toggles the node.
    const beforeClickVisibleExtraLevels = getVisibleExtraLevels(node);
    const beforeClickFoldSnapshot = snapshotSubtreeFolds(node);

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setActiveSelectionFromRenderedElement(
          el,
          beforeClickVisibleExtraLevels,
          beforeClickFoldSnapshot
        );
      });
    });
  },
  true
);




  document.addEventListener(
    "keydown",
    e => {
      if (isEditableTarget(e.target)) return;

      // Important:
      // Capture plain s / d here and stop the older global-depth handler
      // from the first script from running.
      if (
        !e.shiftKey &&
        (e.key === "d" || e.key === "D" || e.key === "s" || e.key === "S")
      ) {
        e.preventDefault();
        e.stopImmediatePropagation();

        if (e.key === "d" || e.key === "D") {
          adjustActiveSelectionLevels(1);
        } else {
          adjustActiveSelectionLevels(-1);
        }

        return;
      }

      if (e.key === "Shift" && !e.repeat) {
        shiftNavActive = true;
        shiftNavBuffer = "";
        showHud("Shift nav: AB / ABZ or X~Y / X~Y~Z", 0);
        return;
      }

      if (!e.shiftKey) return;

      const navChar = getNavCharFromEvent(e);
      if (!navChar) return;

      shiftNavActive = true;

      e.preventDefault();
      e.stopImmediatePropagation();

      if (e.repeat) return;

      if (shiftNavBuffer.length < MAX_SEQUENCE_LENGTH) {
        shiftNavBuffer += navChar;
      }

      showSequenceHud(shiftNavBuffer);
    },
    true
  );

  document.addEventListener(
    "keyup",
    e => {
      if (e.key !== "Shift") return;
      if (!shiftNavActive) return;

      const sequence = shiftNavBuffer;

      shiftNavActive = false;
      shiftNavBuffer = "";

      if (sequence.length >= 2) {
        e.preventDefault();
        e.stopImmediatePropagation();
        executeShiftNavigation(sequence);
      } else {
        showHud("Shift nav cancelled");
      }
    },
    true
  );

  window.addEventListener("blur", () => {
    shiftNavActive = false;
    shiftNavBuffer = "";
  });
})();
</script>
"""
)


def replace_html_title(html_path: Path, title: str) -> None:
    safe_title = html_lib.escape((title or "markmap").strip() or "markmap", quote=False)

    html_text = read_text(html_path)

    html_text, count = re.subn(
        r"<title>.*?</title>",
        lambda _: f"<title>{safe_title}</title>",
        html_text,
        count=1,
        flags=re.IGNORECASE | re.DOTALL,
    )

    if count == 0:
        raise SystemExit(f"[!] <title>...</title> not found in {html_path}")

    write_text(html_path, html_text)


# ─────────────────────────────────────────────────────────────
# Dependency checks
# ─────────────────────────────────────────────────────────────


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def ensure_markmap_cli() -> None:
    if command_exists("markmap"):
        return

    print("[*] markmap not found. Installing markmap-cli globally...")

    if not command_exists("npm"):
        raise SystemExit("[!] npm is required to install markmap-cli.")

    subprocess.run(
        ["npm", "install", "-g", "markmap-cli"],
        check=True,
    )


# ─────────────────────────────────────────────────────────────
# Filename handling
# ─────────────────────────────────────────────────────────────


def ensure_html_favicon(
    html_path: Path,
    favicon_url: str = MARKMAP_FAVICON_URL,
) -> None:
    html = read_text(html_path)

    safe_url = html_lib.escape(favicon_url, quote=True)
    favicon_link = f'<link rel="icon" href="{safe_url}">'

    link_tag_pattern = re.compile(
        r"<link\b[^>]*>",
        flags=re.IGNORECASE | re.DOTALL,
    )

    def is_icon_link(tag: str) -> bool:
        return (
            re.search(
                r'\brel\s*=\s*["\'][^"\']*(?:shortcut\s+icon|icon)[^"\']*["\']',
                tag,
                flags=re.IGNORECASE,
            )
            is not None
        )

    link_tags = list(link_tag_pattern.finditer(html))
    icon_tags = [match for match in link_tags if is_icon_link(match.group(0))]

    if icon_tags:
        first = icon_tags[0]
        html = html[: first.start()] + favicon_link + html[first.end() :]

        # Remove duplicate favicon links after replacing the first one.
        html = link_tag_pattern.sub(
            lambda match: "" if is_icon_link(match.group(0)) else match.group(0),
            html,
            count=len(icon_tags) - 1,
        )

        write_text(html_path, html)
        return

    if re.search(r"<head\b[^>]*>", html, flags=re.IGNORECASE):
        html = re.sub(
            r"(<head\b[^>]*>)",
            rf"\1\n{favicon_link}",
            html,
            count=1,
            flags=re.IGNORECASE,
        )
        write_text(html_path, html)
        return

    raise SystemExit(f"[!] <head> not found in {html_path}")


def truncate_utf8(value: str, max_bytes: int) -> str:
    encoded = value.encode("utf-8")

    if len(encoded) <= max_bytes:
        return value

    return encoded[:max_bytes].decode("utf-8", "ignore").rstrip("._- ")


def make_outfile_path(title: str, outdir: Path | None = None) -> Path:
    outdir = (outdir or Path.cwd()).expanduser().resolve()
    raw = title or ""

    name = unicodedata.normalize("NFKC", raw)

    bad_chars = '/\\:*?"<>|'

    name = "".join(
        "_" if ch in bad_chars or ord(ch) < 32 or ord(ch) == 127 else ch for ch in name
    )

    name = re.sub(r"\s+", "_", name, flags=re.UNICODE)

    name = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)

    name = re.sub(r"_+", "_", name).strip("._- ")

    if not name or name in {".", ".."}:
        digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:8]
        name = f"markmap_{digest}"

    name = truncate_utf8(name, 90)

    if not name:
        name = "markmap"

    candidate = outdir / f"{name}.html"

    if not candidate.exists():
        return candidate

    for i in range(2, 10000):
        suffix = f"_{i}"
        base = truncate_utf8(name, 90 - len(suffix))
        candidate = outdir / f"{base}{suffix}.html"

        if not candidate.exists():
            return candidate

    digest = hashlib.sha256(raw.encode("utf-8", "ignore")).hexdigest()[:12]
    return outdir / f"markmap_{digest}.html"


# ─────────────────────────────────────────────────────────────
# Markdown / frontmatter helpers
# ─────────────────────────────────────────────────────────────


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def find_frontmatter(lines: list[str]) -> tuple[int, int] | None:
    if not lines or lines[0].strip() != "---":
        return None

    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return 0, i

    return None


def find_markmap_section(
    lines: list[str],
    frontmatter: tuple[int, int],
) -> tuple[int, int, str] | None:
    start, end = frontmatter

    for i in range(start + 1, end):
        line = lines[i].rstrip("\r\n")

        match = re.match(r"^markmap\s*:\s*(.*?)\s*(?:#.*)?$", line)

        if not match:
            continue

        inline_value = match.group(1).strip()
        section_end = end

        for j in range(i + 1, end):
            candidate = lines[j]

            if candidate.strip() == "" or candidate.lstrip().startswith("#"):
                continue

            is_top_level = not candidate.startswith((" ", "\t"))
            is_key = re.match(r"^[A-Za-z0-9_-]+\s*:", candidate) is not None

            if is_top_level and is_key:
                section_end = j
                break

        return i, section_end, inline_value

    return None


def strip_surrounding_quotes(value: str) -> str:
    value = value.strip()

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]

    return value


def extract_title(path: Path) -> str:
    text = read_text(path)

    for line in text.splitlines():
        match = re.match(r"^#\s+(.+?)\s*$", line)

        if match:
            title = match.group(1).strip()

            if title:
                return title

    lines = text.splitlines(True)
    frontmatter = find_frontmatter(lines)

    if frontmatter:
        start, end = frontmatter

        for line in lines[start + 1 : end]:
            match = re.match(r"^title\s*:\s*(.*?)\s*(?:#.*)?$", line.rstrip("\r\n"))

            if match:
                title = strip_surrounding_quotes(match.group(1))

                if title:
                    return title

    return "markmap"


def yaml_section_has_key(
    lines: list[str],
    section_start: int,
    section_end: int,
    key: str,
    inline_value: str = "",
) -> bool:
    if inline_value:
        inline_pattern = rf"(?:^|[{{,\s]){re.escape(key)}\s*:"

        if re.search(inline_pattern, inline_value):
            return True

    pattern = re.compile(rf"^\s*{re.escape(key)}\s*:")

    for i in range(section_start + 1, section_end):
        if pattern.match(lines[i]):
            return True

    return False


def detect_child_indent(
    lines: list[str],
    section_start: int,
    section_end: int,
) -> str:
    for i in range(section_start + 1, section_end):
        line = lines[i]

        if not line.strip() or line.lstrip().startswith("#"):
            continue

        match = re.match(r"^(\s+)[A-Za-z0-9_-]+\s*:", line)

        if match:
            return match.group(1)

    return "  "


def normalize_inline_markmap_if_possible(
    lines: list[str],
    section_start: int,
    inline_value: str,
) -> bool:
    raw = inline_value.strip()

    if not raw:
        return False

    if raw == "{}":
        lines[section_start] = "markmap:\n"
        return True

    if not (raw.startswith("{") and raw.endswith("}")):
        return False

    inner = raw[1:-1].strip()
    entries: list[str] = []

    if inner:
        for part in inner.split(","):
            part = part.strip()

            if not part or ":" not in part:
                continue

            key, value = part.split(":", 1)
            key = key.strip()
            value = value.strip()

            if key:
                entries.append(f"  {key}: {value}\n")

    lines[section_start] = "markmap:\n"
    lines[section_start + 1 : section_start + 1] = entries

    return True


def has_markmap_color_freeze_level(path: Path) -> bool:
    text = read_text(path)
    lines = text.splitlines(True)

    frontmatter = find_frontmatter(lines)

    if not frontmatter:
        return False

    section = find_markmap_section(lines, frontmatter)

    if not section:
        return False

    section_start, section_end, inline_value = section

    return yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "colorFreezeLevel",
        inline_value,
    )


def sanitize_max_width(value: str | None) -> str:
    value = (value or "").strip()

    if not value:
        return DEFAULT_MAX_WIDTH

    if not re.fullmatch(r"\d+", value):
        print(f"[!] Invalid maxWidth {value!r}; using {DEFAULT_MAX_WIDTH}.")
        return DEFAULT_MAX_WIDTH

    return str(int(value))


def sanitize_color_freeze_level(value: str | None) -> str:
    value = (value or "").strip()

    if not value:
        return DEFAULT_COLOR_FREEZE_LEVEL

    if not re.fullmatch(r"\d+", value):
        print(
            f"[!] Invalid colorFreezeLevel {value!r}; "
            f"using {DEFAULT_COLOR_FREEZE_LEVEL}."
        )
        return DEFAULT_COLOR_FREEZE_LEVEL

    return str(int(value))


def ensure_markmap_options(
    path: Path,
    color_freeze_level: str | None = None,
    initial_expand_level: str = INITIAL_EXPAND_LEVEL,
    max_width: str | None = DEFAULT_MAX_WIDTH,
) -> None:
    text = read_text(path)
    lines = text.splitlines(True)

    frontmatter = find_frontmatter(lines)

    if frontmatter is None:
        block = [
            "---\n",
            "markmap:\n",
        ]

        if color_freeze_level is not None:
            block.append(
                f"  colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
            )

        if max_width is not None:
            block.append(f"  maxWidth: {sanitize_max_width(max_width)}\n")

        block.extend(
            [
                f"  initialExpandLevel: {initial_expand_level}\n",
                "---\n",
            ]
        )

        write_text(path, "".join(block + lines))
        return

    start, end = frontmatter
    section = find_markmap_section(lines, frontmatter)

    if section is None:
        insert = ["markmap:\n"]

        if color_freeze_level is not None:
            insert.append(
                f"  colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
            )

        if max_width is not None:
            insert.append(f"  maxWidth: {sanitize_max_width(max_width)}\n")

        insert.append(f"  initialExpandLevel: {initial_expand_level}\n")

        lines = lines[:end] + insert + lines[end:]
        write_text(path, "".join(lines))
        return

    section_start, section_end, inline_value = section

    if normalize_inline_markmap_if_possible(lines, section_start, inline_value):
        frontmatter = find_frontmatter(lines)

        if frontmatter is None:
            raise SystemExit(
                "[!] Failed to re-read frontmatter after normalizing inline markmap config."
            )

        section = find_markmap_section(lines, frontmatter)

        if section is None:
            raise SystemExit(
                "[!] Failed to re-read markmap section after normalizing inline config."
            )

        section_start, section_end, inline_value = section

    indent = detect_child_indent(lines, section_start, section_end)

    has_color_freeze_level = yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "colorFreezeLevel",
        inline_value,
    )

    has_max_width = yaml_section_has_key(
        lines,
        section_start,
        section_end,
        "maxWidth",
        inline_value,
    )

    has_initial_expand_level = False

    for i in range(section_start + 1, section_end):
        if re.match(r"^\s*initialExpandLevel\s*:", lines[i]):
            lines[i] = (
                re.sub(
                    r"^(\s*initialExpandLevel\s*:).*$",
                    rf"\1 {initial_expand_level}",
                    lines[i].rstrip("\r\n"),
                )
                + "\n"
            )
            has_initial_expand_level = True
            break

    insertions: list[str] = []

    if color_freeze_level is not None and not has_color_freeze_level:
        insertions.append(
            f"{indent}colorFreezeLevel: {sanitize_color_freeze_level(color_freeze_level)}\n"
        )

    if max_width is not None and not has_max_width:
        insertions.append(f"{indent}maxWidth: {sanitize_max_width(max_width)}\n")

    if not has_initial_expand_level:
        insertions.append(f"{indent}initialExpandLevel: {initial_expand_level}\n")

    if insertions:
        lines = lines[: section_start + 1] + insertions + lines[section_start + 1 :]

    write_text(path, "".join(lines))


# ─────────────────────────────────────────────────────────────
# Interactive input helpers
# ─────────────────────────────────────────────────────────────


def open_tty():
    if os.name == "posix" and Path("/dev/tty").exists():
        reader = open("/dev/tty", "r", encoding="utf-8", errors="replace")
        writer = open("/dev/tty", "w", encoding="utf-8", errors="replace")
        return reader, writer, True

    return sys.stdin, sys.stdout, False


def prompt_with_timeout(
    prompt: str,
    default: str,
    timeout_seconds: int = 2,
) -> str:
    reader, writer, should_close = open_tty()

    try:
        writer.write(prompt)
        writer.flush()

        if select is not None and hasattr(reader, "fileno") and reader.isatty():
            ready, _, _ = select.select([reader], [], [], timeout_seconds)

            if not ready:
                writer.write("\n")
                writer.flush()
                return default

        line = reader.readline()

        if line == "":
            return default

        value = line.rstrip("\n").strip()

        return value if value else default

    finally:
        if should_close:
            reader.close()
            writer.close()


def read_file_paths_interactive() -> list[Path]:
    reader, writer, should_close = open_tty()

    paths: list[Path] = []

    try:
        writer.write("→ No content detected. Switching to file mode.\n")
        writer.write("Enter .md file paths, one per line.\n")
        writer.write("Press Ctrl-D or empty line to finish.\n")
        writer.write("  files ↓\n")
        writer.flush()

        while True:
            line = reader.readline()

            if line == "":
                break

            raw = line.strip()

            if not raw:
                break

            path = Path(raw).expanduser()

            if not path.is_file():
                writer.write(f"  ⚠  File not found: {raw} (skipped)\n")
                writer.flush()
                continue

            paths.append(path.resolve())

    finally:
        if should_close:
            reader.close()
            writer.close()

    return paths


# ─────────────────────────────────────────────────────────────
# HTML patching
# ─────────────────────────────────────────────────────────────


def append_css_code_to_html(html_path: Path) -> None:
    css = CSS_CODE

    if not css.strip():
        return

    html = read_text(html_path)

    # Avoid duplicate insertion if the file is patched more than once.
    if 'id="mm-custom-css"' in html:
        return

    marker = "</head>"

    if marker not in html:
        raise SystemExit(f"[!] </head> not found in {html_path}")

    html = html.replace(marker, css + "\n" + marker, 1)
    write_text(html_path, html)


def append_new_code_to_html(html_path: Path) -> None:
    code = NEW_CODE

    if not code.strip():
        return

    html = read_text(html_path)
    marker = "</body>"

    if marker not in html:
        raise SystemExit(f"[!] </body> not found in {html_path}")

    html = html.replace(marker, code + "\n" + marker, 1)
    write_text(html_path, html)


# ─────────────────────────────────────────────────────────────
# Rendering
# ─────────────────────────────────────────────────────────────


def run_markmap(markdown_path: Path, outfile: Path) -> None:
    subprocess.run(
        [
            "markmap",
            str(markdown_path),
            "-o",
            str(outfile),
            "--no-open",
        ],
        check=True,
    )


def render_markdown_file(markdown_path: Path) -> None:
    markdown_path = markdown_path.expanduser().resolve()

    if not markdown_path.is_file():
        print(f"  ⚠  File not found: {markdown_path} (skipped)")
        return

    color_freeze_level = None

    if not has_markmap_color_freeze_level(markdown_path):
        color_freeze_level = DEFAULT_COLOR_FREEZE_LEVEL

    ensure_markmap_options(
        markdown_path,
        color_freeze_level=color_freeze_level,
    )

    if markdown_path.suffix.lower() == ".md":
        outfile = markdown_path.with_suffix(".html")
    else:
        outfile = Path(str(markdown_path) + ".html")

    #   run_markmap(markdown_path, outfile)
    #   append_new_code_to_html(outfile)
    title = extract_title(markdown_path)

    run_markmap(markdown_path, outfile)

    ensure_html_favicon(outfile)
    replace_html_title(outfile, title)

    append_css_code_to_html(outfile)
    append_new_code_to_html(outfile)

    print(f"[✓] {markdown_path} → {BR}{outfile}{RS}")


def render_markdown_content(markdown_text: str) -> None:
    tmp_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".md",
            prefix="markmap_input_",
            delete=False,
            encoding="utf-8",
        ) as tmp:
            tmp.write(markdown_text)
            tmp_path = Path(tmp.name)

        color_freeze_level = None

        if not has_markmap_color_freeze_level(tmp_path):
            value = prompt_with_timeout(
                f"colorFreezeLevel [{DEFAULT_COLOR_FREEZE_LEVEL}] (2s timeout): ",
                default=DEFAULT_COLOR_FREEZE_LEVEL,
                timeout_seconds=2,
            )
            color_freeze_level = sanitize_color_freeze_level(value)

        ensure_markmap_options(
            tmp_path,
            color_freeze_level=color_freeze_level,
        )

        title = extract_title(tmp_path)
        outfile = make_outfile_path(title)

        run_markmap(tmp_path, outfile)
        ensure_html_favicon(outfile)
        replace_html_title(outfile, title)
        append_css_code_to_html(outfile)
        append_new_code_to_html(outfile)

        # print(f"[✓] Rendered → {BR}{outfile}{RS}")
        # print(f"[✓] Rendered → \n{BR}{outfile}{RS}")
        print(f"[✓] Rendered → \n\n\n{BR}{outfile}{RS}\n\n")

    finally:
        if tmp_path is not None:
            try:
                tmp_path.unlink()
            except FileNotFoundError:
                pass


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────


def is_empty_or_filler(markdown_text: str) -> bool:
    trimmed = "".join(markdown_text.split())
    return trimmed in FILLER_INPUTS


def main() -> None:
    ensure_markmap_cli()

    if len(sys.argv) > 1:
        for raw in sys.argv[1:]:
            render_markdown_file(Path(raw))
        return

    print("=== Markmap Renderer ===")
    print("Type/paste your markdown below. Press Ctrl-D when done.")
    print("(Leave empty — or type only n / N / 呢 / 你 / 能 — to switch to file mode)")
    print("---")

    markdown_text = sys.stdin.read()
    print("")

    if is_empty_or_filler(markdown_text):
        files = read_file_paths_interactive()

        if not files:
            raise SystemExit("No valid files provided. Exiting.")

        for markdown_path in files:
            render_markdown_file(markdown_path)

        return

    render_markdown_content(markdown_text)


if __name__ == "__main__":
    main()
