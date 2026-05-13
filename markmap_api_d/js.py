JS_CODE = r"""<script>
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
        fill: rgba(255, 193, 7, 0.18);
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

    if (e.key === "d" ||  e.key === "D") {
      e.preventDefault();
      setVisibleDepth(mm, Math.min(visibleDepth + 1, maxDepth));
      setTimeout(() => fit(mm), 330);
      return;
    }

    if (e.key === "s" ||  e.key === "S"   ) {
      e.preventDefault();
      setVisibleDepth(mm, Math.max(visibleDepth - 1, 1));
      setTimeout(() => fit(mm), 330);
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

<script>
(() => {
  const MAX_SEQUENCE_LENGTH = 32;
  const RENDER_SETTLE_MS = 360;

  // Zoom tuning.
  // Zoom window = selected node + rendered descendants within requested expanded levels.
  const FOCUS_ZOOM_DURATION_MS = 320;
  const FOCUS_MIN_SCALE = 0.12;
  const FOCUS_MAX_SCALE = 2.25;
  const FOCUS_PADDING_X = 180;
  const FOCUS_PADDING_Y = 120;

  let shiftNavActive = false;
  let shiftNavBuffer = "";
  let hudTimer = null;

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

  function getNodeText(node) {
    return String(
      node?.content ||
      node?.payload?.text ||
      node?.payload?.label ||
      node?.payload?.title ||
      ""
    ).replace(/<[^>]*>/g, "").trim();
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
        fill: rgba(41, 98, 255, 0.13);
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

    hud.textContent = message;

    clearTimeout(hudTimer);

    if (timeout > 0) {
      hudTimer = setTimeout(() => {
        hud.remove();
      }, timeout);
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
    // Also remove old dashed scope boxes if they exist from a previous version.
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

    // Important:
    // No dashed visual box is drawn here.
    // The union is only used internally as the zoom window.
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

    const FOCUS_OFFSET_X = -80;
    const translateX = viewport.width / 2 - centerX * scale + FOCUS_OFFSET_X;
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

  document.addEventListener(
    "keydown",
    e => {
      if (isEditableTarget(e.target)) return;

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
