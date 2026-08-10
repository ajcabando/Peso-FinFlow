/* ============================================================
   Peso-FinFlow — marketing site JS
   1. 3D animated hero (Three.js, vendored, offline-capable)
   2. Scroll-reveal animations
   3. Mobile nav + guide tabs
   ============================================================ */

const prefersReducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)"
).matches;

/* ---------- 1. 3D hero scene ---------- */

function initScene() {
  const canvas = document.getElementById("scene");
  if (!canvas || !window.THREE) return;

  // Reduced motion: render a single static frame, never animate.
  const animate = !prefersReducedMotion;

  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: "high-performance",
    });
  } catch (e) {
    canvas.style.display = "none";
    return;
  }

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);
  camera.position.z = 9;

  /* --- floating particles (soft money sparkles) --- */
  const particleCount = 260;
  const positions = new Float32Array(particleCount * 3);
  const colors = new Float32Array(particleCount * 3);
  const palette = [0x9c6bff, 0x6d5df6, 0x4e9bff, 0x16c784, 0xf5a623];
  for (let i = 0; i < particleCount; i++) {
    const i3 = i * 3;
    // Distribute in a sphere shell.
    const r = 3.5 + Math.random() * 5;
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.acos(2 * Math.random() - 1);
    positions[i3] = r * Math.sin(phi) * Math.cos(theta);
    positions[i3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i3 + 2] = r * Math.cos(phi);

    const c = new THREE.Color(palette[i % palette.length]);
    colors[i3] = c.r;
    colors[i3 + 1] = c.g;
    colors[i3 + 2] = c.b;
  }

  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  pGeo.setAttribute("color", new THREE.BufferAttribute(colors, 3));

  const pMat = new THREE.PointsMaterial({
    size: 0.07,
    vertexColors: true,
    transparent: true,
    opacity: 0.75,
    sizeAttenuation: true,
    depthWrite: false,
  });
  const points = new THREE.Points(pGeo, pMat);
  scene.add(points);

  /* --- rotating icosahedron wireframe (the "ledger orb") --- */
  const orb = new THREE.Mesh(
    new THREE.IcosahedronGeometry(2.1, 1),
    new THREE.MeshBasicMaterial({
      color: 0x9c6bff,
      wireframe: true,
      transparent: true,
      opacity: 0.16,
    })
  );
  scene.add(orb);

  /* --- inner glow sphere --- */
  const glow = new THREE.Mesh(
    new THREE.IcosahedronGeometry(1.15, 3),
    new THREE.MeshBasicMaterial({
      color: 0x6d5df6,
      transparent: true,
      opacity: 0.05,
    })
  );
  scene.add(glow);

  /* --- mouse parallax --- */
  const target = { x: 0, y: 0 };
  const current = { x: 0, y: 0 };
  window.addEventListener("pointermove", (e) => {
    target.x = (e.clientX / window.innerWidth) * 2 - 1;
    target.y = (e.clientY / window.innerHeight) * 2 - 1;
  });

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  /* --- drift animation --- */
  const start = performance.now();
  const raf = (now) => {
    requestAnimationFrame(raf);

    // Pause the render loop when the hero isn't on screen (saves GPU).
    const rect = canvas.getBoundingClientRect();
    const onScreen =
      rect.bottom > 0 && rect.top < window.innerHeight && !document.hidden;
    if (!onScreen) return;

    const t = (now - start) / 1000;
    current.x += (target.x - current.x) * 0.03;
    current.y += (target.y - current.y) * 0.03;

    points.rotation.y = t * 0.05;
    points.rotation.x = Math.sin(t * 0.07) * 0.2;
    orb.rotation.y = t * 0.12;
    orb.rotation.x = t * 0.06;
    glow.rotation.y = -t * 0.05;

    camera.position.x = current.x * 0.9;
    camera.position.y = current.y * 0.6;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  };
  requestAnimationFrame(raf);
}

/* ---------- 2. Scroll reveal ---------- */

function initReveals() {
  const els = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window) || prefersReducedMotion) {
    els.forEach((el) => el.classList.add("visible"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          io.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.12 }
  );
  els.forEach((el) => io.observe(el));
}

/* ---------- 3. Mobile nav + guide tabs ---------- */

function initNav() {
  const toggle = document.getElementById("navToggle");
  const links = document.getElementById("navLinks");
  if (!toggle || !links) return;

  // Resolve data-app-link anchors to the computed app URL once.
  const appUrl = window.FINFLOW_APP_URL;
  if (appUrl) {
    document.querySelectorAll("a[data-app-link]").forEach((a) => {
      a.href = appUrl;
    });
  }

  const close = () => {
    toggle.classList.remove("open");
    links.classList.remove("open");
    toggle.setAttribute("aria-expanded", "false");
  };

  toggle.addEventListener("click", () => {
    const open = links.classList.toggle("open");
    toggle.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
  });

  links.querySelectorAll("a").forEach((a) => a.addEventListener("click", close));
}

function initTabs() {
  const tabs = document.querySelectorAll(".tab");
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => {
        t.classList.toggle("active", t === tab);
        t.setAttribute("aria-selected", String(t === tab));
      });
      document.querySelectorAll(".guide-panel").forEach((panel) => {
        panel.classList.toggle("active", panel.id === `panel-${tab.dataset.tab}`);
      });
    });
  });
}

/* ---------- Boot ---------- */

function boot() {
  initScene();
  initNav();
  initTabs();
  initReveals();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
