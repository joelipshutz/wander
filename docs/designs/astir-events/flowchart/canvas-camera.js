/* Astir review canvas: dependency-free pan, zoom and touch camera. */
(function (global) {
  "use strict";

  function AstirCanvasCamera(options) {
    if (!(this instanceof AstirCanvasCamera)) return new AstirCanvasCamera(options);
    options = options || {};
    var viewport = options.viewport;
    var world = options.world;
    if (!viewport || !world) throw new Error("A canvas viewport and world are required.");

    var minScale = positive(options.minScale, 0.035);
    var maxScale = Math.max(minScale, positive(options.maxScale, 2));
    var state = { x: 0, y: 0, scale: clamp(1, minScale, maxScale) };
    var pointers = new Map();
    var single = null;
    var pinch = null;
    var dragged = false;
    var destroyed = false;
    var suppressClickUntil = 0;
    var ownerWindow = viewport.ownerDocument.defaultView || global;
    var initialStyles = {
      touchAction: viewport.style.touchAction,
      userSelect: viewport.style.userSelect,
      webkitUserSelect: viewport.style.webkitUserSelect,
      transform: world.style.transform,
      transformOrigin: world.style.transformOrigin
    };
    var initiallyPanning = viewport.classList.contains("is-panning");
    var interactiveSelector = "a, input, textarea, select, [contenteditable]:not([contenteditable='false']), [data-no-pan]";

    viewport.style.touchAction = "none";
    viewport.style.userSelect = "none";
    viewport.style.webkitUserSelect = "none";
    world.style.transformOrigin = "0 0";

    function positive(value, fallback) {
      return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : fallback;
    }

    function finite(value, fallback) {
      return typeof value === "number" && Number.isFinite(value) ? value : fallback;
    }

    function clamp(value, low, high) {
      return Math.max(low, Math.min(high, value));
    }

    function snapshot() {
      return { x: state.x, y: state.y, scale: state.scale };
    }

    function draw(notify) {
      world.style.transform = "translate(" + state.x + "px, " + state.y + "px) scale(" + state.scale + ")";
      if (notify && typeof options.onChange === "function") options.onChange(snapshot());
    }

    function apply(next) {
      if (destroyed) return snapshot();
      var updated = {
        x: finite(next.x, state.x),
        y: finite(next.y, state.y),
        scale: clamp(positive(next.scale, state.scale), minScale, maxScale)
      };
      if (updated.x !== state.x || updated.y !== state.y || updated.scale !== state.scale) {
        state = updated;
        draw(true);
      }
      return snapshot();
    }

    function local(clientX, clientY) {
      var bounds = viewport.getBoundingClientRect();
      return { x: clientX - bounds.left, y: clientY - bounds.top };
    }

    function isInteractive(target) {
      var element = target && (target.nodeType === 1 ? target : target.parentElement);
      return !!(element && element.closest(interactiveSelector));
    }

    function capture(id) {
      try {
        if (!viewport.hasPointerCapture(id)) viewport.setPointerCapture(id);
      } catch (_) {
        // A pointer can end while capture is being requested; window listeners still clean up.
      }
    }

    function release(id) {
      try {
        if (viewport.hasPointerCapture(id)) viewport.releasePointerCapture(id);
      } catch (_) {}
    }

    function setPanning(value) {
      if (value) viewport.classList.add("is-panning");
      else if (!initiallyPanning) viewport.classList.remove("is-panning");
    }

    function geometry(first, second) {
      var midpoint = local((first.x + second.x) / 2, (first.y + second.y) / 2);
      return {
        x: midpoint.x,
        y: midpoint.y,
        distance: Math.max(1, Math.hypot(first.x - second.x, first.y - second.y))
      };
    }

    function startSingle(point, alreadyDragging) {
      single = { id: point.id, x: point.x, y: point.y, baseX: state.x, baseY: state.y, active: alreadyDragging };
      pinch = null;
      if (alreadyDragging) capture(point.id);
    }

    function startPinch() {
      var pair = Array.from(pointers.values()).slice(0, 2);
      var start = geometry(pair[0], pair[1]);
      pinch = {
        ids: [pair[0].id, pair[1].id],
        distance: start.distance,
        scale: state.scale,
        anchorX: (start.x - state.x) / state.scale,
        anchorY: (start.y - state.y) / state.scale,
        startX: start.x,
        startY: start.y
      };
      single = null;
      pair.forEach(function (point) { capture(point.id); });
    }

    function pointerDown(event) {
      if (destroyed || isInteractive(event.target)) return;
      if (event.pointerType === "mouse" && event.button !== 0 && event.button !== 1) return;
      if (pointers.size >= 2) return;
      // Do not prevent default or capture a one-pointer press: screen buttons retain normal clicks.
      if (pointers.size === 0) {
        dragged = false;
        suppressClickUntil = 0;
      }
      pointers.set(event.pointerId, { id: event.pointerId, x: event.clientX, y: event.clientY });
      if (pointers.size === 1) startSingle(pointers.get(event.pointerId), false);
      else startPinch();
      if (event.pointerType === "mouse" && event.button === 1) event.preventDefault();
    }

    function pointerMove(event) {
      var point = pointers.get(event.pointerId);
      if (!point || destroyed) return;
      point.x = event.clientX;
      point.y = event.clientY;
      if (pinch) {
        var first = pointers.get(pinch.ids[0]);
        var second = pointers.get(pinch.ids[1]);
        if (!first || !second) return;
        var current = geometry(first, second);
        var scale = clamp(pinch.scale * current.distance / pinch.distance, minScale, maxScale);
        if (!dragged && (Math.abs(current.distance - pinch.distance) >= 4 ||
            Math.hypot(current.x - pinch.startX, current.y - pinch.startY) >= 4)) dragged = true;
        if (dragged) setPanning(true);
        apply({ x: current.x - pinch.anchorX * scale, y: current.y - pinch.anchorY * scale, scale: scale });
        event.preventDefault();
      } else if (single && single.id === point.id) {
        var dx = point.x - single.x;
        var dy = point.y - single.y;
        if (!single.active && Math.hypot(dx, dy) < 4) return;
        if (!single.active) {
          single.active = true;
          dragged = true;
          capture(point.id);
          setPanning(true);
        }
        apply({ x: single.baseX + dx, y: single.baseY + dy });
        event.preventDefault();
      }
    }

    function endPointer(event) {
      if (!pointers.has(event.pointerId)) return;
      pointers.delete(event.pointerId);
      release(event.pointerId);
      if (dragged) suppressClickUntil = Date.now() + 500;
      if (pointers.size === 1) {
        startSingle(pointers.values().next().value, dragged);
      } else {
        single = null;
        pinch = null;
        setPanning(false);
      }
    }

    function cancelAll() {
      var ids = Array.from(pointers.keys());
      pointers.clear();
      ids.forEach(release);
      if (dragged) suppressClickUntil = Date.now() + 500;
      single = null;
      pinch = null;
      dragged = false;
      setPanning(false);
    }

    function click(event) {
      if (Date.now() <= suppressClickUntil) {
        suppressClickUntil = 0;
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }

    function dragStart(event) {
      if (!isInteractive(event.target)) event.preventDefault();
    }

    function wheel(event) {
      if (destroyed || isInteractive(event.target)) return;
      event.preventDefault();
      var bounds = viewport.getBoundingClientRect();
      var unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? bounds.height : 1;
      var dx = event.deltaX * unit;
      var dy = event.deltaY * unit;
      if (event.ctrlKey || event.metaKey) {
        // Browser pinch gestures are wheel events with ctrlKey; preserve the world point under the cursor.
        api.zoomAt(Math.exp(clamp(-dy * 0.01, -1, 1)), event.clientX, event.clientY);
      } else {
        if (event.shiftKey && Math.abs(dx) < 0.01) { dx = dy; dy = 0; }
        api.panBy(-dx, -dy);
      }
    }

    var api = this;
    api.getState = snapshot;
    api.setState = function (next) { return apply(next || {}); };
    api.panBy = function (dx, dy) {
      return apply({ x: state.x + finite(dx, 0), y: state.y + finite(dy, 0) });
    };
    api.zoomAt = function (factor, clientX, clientY) {
      var bounds = viewport.getBoundingClientRect();
      var position = local(finite(clientX, bounds.left + bounds.width / 2), finite(clientY, bounds.top + bounds.height / 2));
      var scale = clamp(state.scale * positive(factor, 1), minScale, maxScale);
      var ratio = scale / state.scale;
      return apply({ x: position.x - (position.x - state.x) * ratio, y: position.y - (position.y - state.y) * ratio, scale: scale });
    };
    api.fitRect = function (rect, padding, fitMaxScale) {
      rect = rect || {};
      var bounds = viewport.getBoundingClientRect();
      var inset = Math.max(0, finite(padding, 60));
      var width = positive(rect.width, 1);
      var height = positive(rect.height, 1);
      var availableWidth = Math.max(1, bounds.width - inset * 2);
      var availableHeight = Math.max(1, bounds.height - inset * 2);
      var limit = clamp(positive(fitMaxScale, 1), minScale, maxScale);
      var scale = clamp(Math.min(availableWidth / width, availableHeight / height, limit), minScale, maxScale);
      return apply({
        x: bounds.width / 2 - (finite(rect.x, 0) + width / 2) * scale,
        y: bounds.height / 2 - (finite(rect.y, 0) + height / 2) * scale,
        scale: scale
      });
    };
    api.destroy = function () {
      if (destroyed) return;
      destroyed = true;
      cancelAll();
      viewport.removeEventListener("pointerdown", pointerDown);
      ownerWindow.removeEventListener("pointermove", pointerMove);
      ownerWindow.removeEventListener("pointerup", endPointer);
      ownerWindow.removeEventListener("pointercancel", endPointer);
      viewport.removeEventListener("lostpointercapture", endPointer);
      ownerWindow.removeEventListener("blur", cancelAll);
      viewport.removeEventListener("click", click, true);
      viewport.removeEventListener("dragstart", dragStart);
      viewport.removeEventListener("wheel", wheel);
      viewport.style.touchAction = initialStyles.touchAction;
      viewport.style.userSelect = initialStyles.userSelect;
      viewport.style.webkitUserSelect = initialStyles.webkitUserSelect;
      world.style.transform = initialStyles.transform;
      world.style.transformOrigin = initialStyles.transformOrigin;
    };

    viewport.addEventListener("pointerdown", pointerDown);
    ownerWindow.addEventListener("pointermove", pointerMove, { passive: false });
    ownerWindow.addEventListener("pointerup", endPointer);
    ownerWindow.addEventListener("pointercancel", endPointer);
    viewport.addEventListener("lostpointercapture", endPointer);
    ownerWindow.addEventListener("blur", cancelAll);
    viewport.addEventListener("click", click, true);
    viewport.addEventListener("dragstart", dragStart);
    viewport.addEventListener("wheel", wheel, { passive: false });
    draw(false);
  }

  global.AstirCanvasCamera = AstirCanvasCamera;
})(window);
