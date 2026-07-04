import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { STLLoader } from "three/addons/loaders/STLLoader.js";

// ---------------------------------------------------------------------------
// Scene setup
// ---------------------------------------------------------------------------
const viewerEl = document.getElementById("viewer");
const loadingEl = document.getElementById("loading");
const emptyEl = document.getElementById("empty-state");

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x11141a);

const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100000);
camera.position.set(120, 90, 140);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
viewerEl.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.autoRotateSpeed = 2.2;
// A drag / wheel / pan means the user took control — stop auto-refitting.
controls.addEventListener("start", () => {
  userAdjusted = true;
});

// Lighting
scene.add(new THREE.AmbientLight(0xffffff, 0.55));
const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(1, 1.4, 1);
scene.add(key);
const fill = new THREE.DirectionalLight(0x88aaff, 0.5);
fill.position.set(-1, 0.5, -1);
scene.add(fill);
const rim = new THREE.DirectionalLight(0xffffff, 0.4);
rim.position.set(0, -1, -0.5);
scene.add(rim);

// Ground grid (sized after each model loads)
let grid = null;

const material = new THREE.MeshStandardMaterial({
  color: 0x6aa9ff,
  metalness: 0.05,
  roughness: 0.55,
  flatShading: false,
});

let currentMesh = null;
const loader = new STLLoader();

// Auto-fit state: keep re-framing the model as the viewport changes (resize,
// late layout, tab reveal) until the user manually moves the camera. This keeps
// the model centered no matter what size the viewer was when it first loaded.
let userAdjusted = false;
let currentDir = null; // last view direction used for framing

// ---------------------------------------------------------------------------
// Rendering loop
// ---------------------------------------------------------------------------
function resize() {
  const w = viewerEl.clientWidth;
  const h = viewerEl.clientHeight;
  if (w === 0 || h === 0) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  // Re-fit to the new viewport unless the user has taken control of the camera.
  if (currentMesh && !userAdjusted) frameCamera(currentDir || undefined, false);
}
window.addEventListener("resize", resize);
new ResizeObserver(resize).observe(viewerEl);
// A backgrounded tab may lay out at a stale size; re-fit when it becomes visible.
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) resize();
});

// Smooth camera tween (shared by framing + gizmo). While a tween is active we
// drive camera.position / controls.target directly and let OrbitControls resync.
const clock = new THREE.Clock();
let camTween = null;
const easeInOutCubic = (t) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

function tweenCamera(toPos, toTarget, animated = true) {
  if (!animated) {
    camera.position.copy(toPos);
    controls.target.copy(toTarget);
    controls.update();
    camTween = null;
    return;
  }
  camTween = {
    fromPos: camera.position.clone(),
    toPos: toPos.clone(),
    fromTgt: controls.target.clone(),
    toTgt: toTarget.clone(),
    t: 0,
    dur: 0.4,
  };
}

function animate() {
  requestAnimationFrame(animate);
  const dt = clock.getDelta();
  if (camTween) {
    camTween.t = Math.min(1, camTween.t + dt / camTween.dur);
    const k = easeInOutCubic(camTween.t);
    camera.position.lerpVectors(camTween.fromPos, camTween.toPos, k);
    controls.target.lerpVectors(camTween.fromTgt, camTween.toTgt, k);
    if (camTween.t >= 1) camTween = null;
  }
  controls.update();
  renderer.render(scene, camera);
}
resize();
animate();

// ---------------------------------------------------------------------------
// Model loading
// ---------------------------------------------------------------------------
// Standard view directions cycled by the gizmo cube button (iso is the default).
const VIEW_DIRS = [
  new THREE.Vector3(0.9, 0.7, 1), // iso
  new THREE.Vector3(0, 0, 1), // front
  new THREE.Vector3(1, 0, 0.001), // right
  new THREE.Vector3(0.001, 1, 0.001), // top
  new THREE.Vector3(-0.9, 0.7, -1), // back-iso
].map((v) => v.normalize());

let lastFitDist = 200; // used to clamp gizmo zoom
let modelCenter = new THREE.Vector3();

// Place the model once on load: center its footprint on the origin and rest its
// base on the grid. Framing the camera is a separate concern (see frameCamera).
function placeModel(mesh) {
  const box = new THREE.Box3().setFromObject(mesh);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());

  mesh.position.x -= center.x;
  mesh.position.z -= center.z;
  mesh.position.y -= box.min.y; // sit base on the grid (y = 0)

  const maxDim = Math.max(size.x, size.y, size.z) || 1;

  // Rebuild grid to roughly match footprint
  if (grid) scene.remove(grid);
  const gridSize = Math.ceil((maxDim * 2.2) / 10) * 10;
  grid = new THREE.GridHelper(gridSize, gridSize / 10, 0x3a4456, 0x222a36);
  scene.add(grid);

  return { size, triangles: mesh.geometry.attributes.position.count / 3 };
}

// Frame the current model so it's centered and fully visible for the *current*
// viewport aspect. Uses the bounding sphere and the smaller of the horizontal /
// vertical FOV so wide and tall parts both fit without cropping.
function frameCamera(dir = VIEW_DIRS[0], animated = true) {
  if (!currentMesh) return;
  currentDir = dir.clone().normalize();
  const box = new THREE.Box3().setFromObject(currentMesh);
  const sphere = box.getBoundingSphere(new THREE.Sphere());
  modelCenter.copy(sphere.center);

  const vFov = (camera.fov * Math.PI) / 180;
  const hFov = 2 * Math.atan(Math.tan(vFov / 2) * camera.aspect);
  const fitFov = Math.min(vFov, hFov);
  const fitDist = (sphere.radius / Math.sin(fitFov / 2)) * 1.15;
  lastFitDist = fitDist;

  camera.near = Math.max(fitDist / 1000, 0.01);
  camera.far = fitDist * 1000;
  camera.updateProjectionMatrix();

  const target = sphere.center.clone();
  const camPos = target.clone().add(dir.clone().normalize().multiplyScalar(fitDist));
  tweenCamera(camPos, target, animated);
}

// ---- Gizmo motion: orbit and zoom around the current target ----
function orbit(dThetaDeg, dPhiDeg) {
  userAdjusted = true; // user chose a view; stop auto-refitting on resize
  const offset = camera.position.clone().sub(controls.target);
  const sph = new THREE.Spherical().setFromVector3(offset);
  sph.theta += (dThetaDeg * Math.PI) / 180;
  sph.phi = Math.max(0.12, Math.min(Math.PI - 0.12, sph.phi + (dPhiDeg * Math.PI) / 180));
  offset.setFromSpherical(sph);
  tweenCamera(controls.target.clone().add(offset), controls.target.clone(), true);
}

function zoom(factor) {
  userAdjusted = true;
  const offset = camera.position.clone().sub(controls.target);
  const sph = new THREE.Spherical().setFromVector3(offset);
  sph.radius = Math.max(lastFitDist * 0.25, Math.min(lastFitDist * 6, sph.radius * factor));
  offset.setFromSpherical(sph);
  tweenCamera(controls.target.clone().add(offset), controls.target.clone(), true);
}

let viewIndex = 0;
function cycleView() {
  userAdjusted = false; // a deliberate fit; keep it fitted through resizes
  viewIndex = (viewIndex + 1) % VIEW_DIRS.length;
  frameCamera(VIEW_DIRS[viewIndex], true);
}
function resetView() {
  userAdjusted = false;
  viewIndex = 0;
  frameCamera(VIEW_DIRS[0], true);
}

function clearMesh() {
  if (currentMesh) {
    scene.remove(currentMesh);
    currentMesh.geometry.dispose();
    currentMesh = null;
  }
}

function loadModel(model) {
  loadingEl.hidden = false;
  clearMesh();

  loader.load(
    model.stl,
    (geometry) => {
      geometry.computeVertexNormals();
      const mesh = new THREE.Mesh(geometry, material);
      // STL is Z-up (OpenSCAD); rotate to three.js Y-up
      mesh.rotation.x = -Math.PI / 2;
      scene.add(mesh);
      currentMesh = mesh;
      const stats = placeModel(mesh);
      userAdjusted = false; // new model → resume auto-fit
      frameCamera(VIEW_DIRS[0], false);
      viewIndex = 0;
      updateInfo(model, stats);
      loadingEl.hidden = true;
    },
    undefined,
    (err) => {
      console.error("Failed to load STL", model.stl, err);
      loadingEl.hidden = true;
      document.getElementById("info-title").textContent = "Failed to load model";
      document.getElementById("info-desc").textContent = model.stl;
    }
  );
}

// ---------------------------------------------------------------------------
// UI / info panel
// ---------------------------------------------------------------------------
const btnDownload = document.getElementById("btn-download");

function fmt(n) {
  return n.toLocaleString(undefined, { maximumFractionDigits: 1 });
}

function updateInfo(model, stats) {
  document.getElementById("info-title").textContent = model.title;
  document.getElementById("info-project").textContent = model.project;
  document.getElementById("info-desc").textContent = model.description || "";

  const dl = document.getElementById("info-stats");
  dl.innerHTML = "";
  if (stats) {
    const dims = `${fmt(stats.size.x)} × ${fmt(stats.size.z)} × ${fmt(stats.size.y)} mm`;
    addStat(dl, "Bounding box", dims);
    addStat(dl, "Triangles", fmt(stats.triangles));
  }

  const src = document.getElementById("info-source");
  if (model.source) {
    src.href = model.source;
    src.hidden = false;
  } else {
    src.hidden = true;
  }

  btnDownload.href = model.stl;
  btnDownload.style.display = "inline-block";
}

function addStat(dl, label, value) {
  const dt = document.createElement("dt");
  dt.textContent = label;
  const dd = document.createElement("dd");
  dd.textContent = value;
  dl.append(dt, dd);
}

let activeEl = null;
function buildList(models) {
  const listEl = document.getElementById("model-list");
  listEl.innerHTML = "";

  const byProject = new Map();
  for (const m of models) {
    if (!byProject.has(m.project)) byProject.set(m.project, []);
    byProject.get(m.project).push(m);
  }

  for (const [project, items] of byProject) {
    const group = document.createElement("div");
    group.className = "project-group";
    const label = document.createElement("div");
    label.className = "project-label";
    label.textContent = project;
    group.appendChild(label);

    for (const m of items) {
      const item = document.createElement("div");
      item.className = "model-item";
      item.dataset.search = `${m.title} ${m.project} ${m.name}`.toLowerCase();

      if (m.preview) {
        const img = document.createElement("img");
        img.className = "model-thumb";
        img.src = m.preview;
        img.alt = "";
        img.loading = "lazy";
        item.appendChild(img);
      } else {
        const ph = document.createElement("div");
        ph.className = "model-thumb placeholder";
        ph.textContent = "🧊";
        item.appendChild(ph);
      }

      const meta = document.createElement("div");
      meta.className = "model-meta";
      const name = document.createElement("div");
      name.className = "model-name";
      name.textContent = m.title;
      const sub = document.createElement("div");
      sub.className = "model-sub";
      sub.textContent = m.model;
      meta.append(name, sub);
      item.appendChild(meta);

      item.addEventListener("click", () => {
        if (activeEl) activeEl.classList.remove("active");
        item.classList.add("active");
        activeEl = item;
        loadModel(m);
        location.hash = encodeURIComponent(m.name);
      });

      group.appendChild(item);
      m._el = item;
    }
    listEl.appendChild(group);
  }
}

// Search filter
document.getElementById("search").addEventListener("input", (e) => {
  const q = e.target.value.trim().toLowerCase();
  for (const item of document.querySelectorAll(".model-item")) {
    item.style.display = !q || item.dataset.search.includes(q) ? "" : "none";
  }
  for (const group of document.querySelectorAll(".project-group")) {
    const anyVisible = [...group.querySelectorAll(".model-item")].some(
      (i) => i.style.display !== "none"
    );
    group.style.display = anyVisible ? "" : "none";
  }
});

// Toolbar
const btnReset = document.getElementById("btn-reset");
const btnWire = document.getElementById("btn-wireframe");
const btnSpin = document.getElementById("btn-spin");

btnReset.addEventListener("click", resetView);
btnWire.addEventListener("click", () => {
  material.wireframe = !material.wireframe;
  btnWire.classList.toggle("on", material.wireframe);
});
btnSpin.addEventListener("click", () => {
  controls.autoRotate = !controls.autoRotate;
  btnSpin.classList.toggle("on", controls.autoRotate);
});

window.addEventListener("keydown", (e) => {
  if (e.target.tagName === "INPUT") return;
  if (e.key === "r" || e.key === "R") btnReset.click();
  if (e.key === "w" || e.key === "W") btnWire.click();
  if (e.key === " ") {
    e.preventDefault();
    btnSpin.click();
  }
});

// ---------------------------------------------------------------------------
// Navigation gizmo (on-screen widget)
// ---------------------------------------------------------------------------
const SVGNS = "http://www.w3.org/2000/svg";
const el = (name, attrs = {}) => {
  const n = document.createElementNS(SVGNS, name);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  return n;
};

function buildGizmo() {
  const cx = 60;
  const cy = 60;
  const R = 54; // outer ring radius
  const r = 27; // inner circle radius
  const pt = (rad, deg) => {
    const a = (deg * Math.PI) / 180;
    return [cx + rad * Math.cos(a), cy + rad * Math.sin(a)];
  };
  // Annular wedge between inner radius r and outer radius R over [a1, a2] deg.
  const wedge = (a1, a2) => {
    const [ix1, iy1] = pt(r, a1);
    const [ox1, oy1] = pt(R, a1);
    const [ox2, oy2] = pt(R, a2);
    const [ix2, iy2] = pt(r, a2);
    return `M${ix1},${iy1} L${ox1},${oy1} A${R},${R} 0 0 1 ${ox2},${oy2} L${ix2},${iy2} A${r},${r} 0 0 0 ${ix1},${iy1} Z`;
  };

  const svg = el("svg", { viewBox: "0 0 120 152", class: "gizmo-svg" });

  // Interactive button: an invisible hit path plus one or more glyph paths.
  const makeBtn = (hitPath, glyphs, title, onClick) => {
    const g = el("g", { class: "gz-btn" });
    const t = el("title");
    t.textContent = title;
    g.appendChild(t);
    g.appendChild(el("path", { class: "gz-fill", d: hitPath }));
    for (const gl of glyphs) g.appendChild(gl);
    g.addEventListener("click", onClick);
    svg.appendChild(g);
    return g;
  };

  const chevron = (pts) =>
    el("polyline", { class: "gz-glyph", points: pts, fill: "none" });

  // --- Bottom tab (drawn first so the ring overlaps it) ---
  svg.appendChild(
    el("rect", { class: "gz-line", x: 22, y: 104, width: 76, height: 40, rx: 12 })
  );
  svg.appendChild(el("line", { class: "gz-line", x1: 60, y1: 112, x2: 60, y2: 144 }));

  // Reset (recenter) button — circular arrow with a small cross.
  makeBtn(
    "M22 112 h38 v32 h-26 a12 12 0 0 1 -12 -12 Z",
    [
      el("path", {
        class: "gz-glyph",
        fill: "none",
        d: "M46 124 a8 8 0 1 0 2 5",
      }),
      el("polyline", { class: "gz-glyph", fill: "none", points: "48 121, 48 129, 40 129" }),
      el("line", { class: "gz-glyph", x1: 38, y1: 124, x2: 42, y2: 132 }),
      el("line", { class: "gz-glyph", x1: 42, y1: 124, x2: 38, y2: 132 }),
    ],
    "Reset view",
    resetView
  );

  // Cube button — cycles standard views (iso → front → right → top → back).
  makeBtn(
    "M60 112 h26 a12 12 0 0 1 12 12 v20 h-38 Z",
    [
      el("polygon", { class: "gz-glyph", fill: "none", points: "80 116, 90 122, 90 132, 80 138, 70 132, 70 122" }),
      el("polyline", { class: "gz-glyph", fill: "none", points: "70 122, 80 128, 90 122" }),
      el("line", { class: "gz-glyph", x1: 80, y1: 128, x2: 80, y2: 138 }),
    ],
    "Cycle standard views",
    cycleView
  );

  // --- Outer ring: four directional wedges (orbit) ---
  makeBtn(wedge(225, 315), [chevron("52 26, 60 18, 68 26")], "Tilt up", () => orbit(0, -22.5));
  makeBtn(wedge(45, 135), [chevron("52 94, 60 102, 68 94")], "Tilt down", () => orbit(0, 22.5));
  makeBtn(wedge(135, 225), [chevron("26 52, 18 60, 26 68")], "Rotate left", () => orbit(-22.5, 0));
  makeBtn(wedge(-45, 45), [chevron("94 52, 102 60, 94 68")], "Rotate right", () => orbit(22.5, 0));
  // Outer ring outline + diagonal segment dividers (on top, non-interactive)
  svg.appendChild(el("circle", { class: "gz-line", cx, cy, r: R, fill: "none" }));
  for (const deg of [45, 135, 225, 315]) {
    const [ix, iy] = pt(r, deg);
    const [ox, oy] = pt(R, deg);
    svg.appendChild(el("line", { class: "gz-line", x1: ix, y1: iy, x2: ox, y2: oy }));
  }

  // --- Inner circle: zoom in (top) / out (bottom) ---
  makeBtn(
    `M${cx - r},${cy} A${r},${r} 0 0 1 ${cx + r},${cy} Z`,
    [
      el("line", { class: "gz-glyph", x1: 60, y1: 40, x2: 60, y2: 52 }),
      el("line", { class: "gz-glyph", x1: 54, y1: 46, x2: 66, y2: 46 }),
    ],
    "Zoom in",
    () => zoom(0.8)
  );
  makeBtn(
    `M${cx - r},${cy} A${r},${r} 0 0 0 ${cx + r},${cy} Z`,
    [el("line", { class: "gz-glyph", x1: 54, y1: 74, x2: 66, y2: 74 })],
    "Zoom out",
    () => zoom(1.25)
  );
  // Inner circle outline + divider (on top, non-interactive)
  svg.appendChild(el("circle", { class: "gz-line", cx, cy, r, fill: "none" }));
  svg.appendChild(el("line", { class: "gz-line", x1: cx - r, y1: cy, x2: cx + r, y2: cy }));

  const mount = document.getElementById("gizmo");
  mount.appendChild(svg);
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------
async function init() {
  let manifest;
  try {
    const res = await fetch("manifest.json", { cache: "no-cache" });
    manifest = await res.json();
  } catch (err) {
    console.error("Failed to load manifest", err);
    emptyEl.hidden = false;
    return;
  }

  if (manifest.repo) {
    const link = document.getElementById("repo-link");
    link.href = `https://github.com/${manifest.repo}`;
  }
  if (manifest.generated) {
    document.getElementById("generated").textContent =
      "Built " + new Date(manifest.generated).toLocaleString();
  }

  const models = manifest.models || [];
  if (models.length === 0) {
    emptyEl.hidden = false;
    return;
  }

  buildList(models);

  // Open model from hash, else first model
  const wanted = decodeURIComponent(location.hash.slice(1));
  const target = models.find((m) => m.name === wanted) || models[0];
  target._el.click();
}

buildGizmo();
init();
