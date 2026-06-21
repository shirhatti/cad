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
}
window.addEventListener("resize", resize);
new ResizeObserver(resize).observe(viewerEl);

function animate() {
  requestAnimationFrame(animate);
  controls.update();
  renderer.render(scene, camera);
}
resize();
animate();

// ---------------------------------------------------------------------------
// Model loading
// ---------------------------------------------------------------------------
function frameObject(mesh) {
  const box = new THREE.Box3().setFromObject(mesh);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());

  // Re-center the mesh so it sits on the grid, centered on origin
  mesh.position.sub(center);
  mesh.position.y += size.y / 2;

  const maxDim = Math.max(size.x, size.y, size.z) || 1;

  // Rebuild grid to roughly match footprint
  if (grid) scene.remove(grid);
  const gridSize = Math.ceil((maxDim * 2.2) / 10) * 10;
  grid = new THREE.GridHelper(gridSize, gridSize / 10, 0x3a4456, 0x222a36);
  scene.add(grid);

  // Position camera to frame the object
  const fitDist = (maxDim / (2 * Math.tan((camera.fov * Math.PI) / 360))) * 1.6;
  const dir = new THREE.Vector3(0.9, 0.7, 1).normalize();
  controls.target.set(0, size.y / 2, 0);
  camera.position.copy(controls.target).add(dir.multiplyScalar(fitDist));
  camera.near = fitDist / 100;
  camera.far = fitDist * 100;
  camera.updateProjectionMatrix();
  controls.update();

  return { size, triangles: mesh.geometry.attributes.position.count / 3 };
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
      const stats = frameObject(mesh);
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

btnReset.addEventListener("click", () => {
  if (currentMesh) frameObject(currentMesh);
});
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

init();
