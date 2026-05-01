import * as three               from 'three';
        import { OrbitControls }        from '/node_modules/three/examples/jsm/controls/OrbitControls.js';
        import { PointerLockControls }  from '/node_modules/three/examples/jsm/controls/PointerLockControls.js';
        import GUI                      from 'https://cdn.jsdelivr.net/npm/lil-gui@0.19/+esm';
        
        //grab shaders from glsl files 
        const [vert, frag] = await Promise.all([
          fetch('/projects/vert.glsl').then(r => r.text()),
          fetch('/projects/frag.glsl').then(r => r.text()),
        ]);

        // Scene & Renderer setup
        const renderer = new three.WebGLRenderer({ antialias: true });

        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(window.devicePixelRatio);
        document.body.appendChild(renderer.domElement);

        const scene = new three.Scene();
        const backgroundColor = new three.Color(0x000000);
        renderer.setClearColor(backgroundColor, 1);

        // Light
        const light = new three.DirectionalLight(0xffffff, 1);
        light.position.set(1, 1, 1);
        scene.add(light);

        // Camera
        const camera = new three.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        camera.position.z = 5;

        // Orbit controls (default)
        const orbit = new OrbitControls(camera, renderer.domElement);
        orbit.enableDamping = true;

        // FPS controls
        const fp = new PointerLockControls(camera, document.body);
        const params = { moveSpeed: 5.0}; 

        // Toggle between first-person and orbit controls
        let isFirstPerson = false;
        window.addEventListener('keydown', (e) => {
            if (e.key.toLowerCase() === 'c') {
                isFirstPerson = !isFirstPerson; // toggle
                orbit.enabled = !isFirstPerson;
                if (isFirstPerson) fp.lock();
                else fp.unlock();
            }
        });

        fp.addEventListener('unlock', () => {
            isFirstPerson = false;
            orbit.enabled = true;
        });

        // WASD state
        const keys = { w: false, a: false, s: false, d: false, e: false, q: false };
        document.addEventListener('keydown', (e) => {
            if (e.code === 'KeyW') keys.w = true;
            if (e.code === 'KeyA') keys.a = true;
            if (e.code === 'KeyS') keys.s = true;
            if (e.code === 'KeyD') keys.d = true;
            if (e.code === 'KeyE') keys.e = true;
            if (e.code === 'KeyQ') keys.q = true;
        });

        document.addEventListener('keyup', (e) => {
            if (e.code === 'KeyW') keys.w = false;
            if (e.code === 'KeyA') keys.a = false;
            if (e.code === 'KeyS') keys.s = false;
            if (e.code === 'KeyD') keys.d = false;
            if (e.code === 'KeyE') keys.e = false;
            if (e.code === 'KeyQ') keys.q = false;
        });
    


        // Uniforms 
        const uniforms = {
            u_hitThresh:        { value: 0.00001 },
            u_maxDist:          { value: 50 },
            u_maxSteps:         { value: 200 },

            u_clearColor:       { value: backgroundColor },
            u_resolution:       { value: new three.Vector2() },

            u_camPos:           { value: camera.position },
            u_camToWorldMat:    { value: camera.matrixWorld },
            u_camInvProjMat:    { value: camera.projectionMatrixInverse },

            u_lightDir:         { value: light.position },
            u_lightColor:       { value: light.color },

            u_diffIntensity:    { value: 0.5 },
            u_specIntensity:    { value: 3 },
            u_ambientIntensity: { value: 0.15 },
            u_shininess:        { value: 16 },


            u_time:             { value: 0 },
        };

        // lil-gui debug panel
        const gui = new GUI({ title: 'Controls' });

        const camFolder   = gui.addFolder('Camera');
        camFolder.add(params, 'moveSpeed', 0.5, 20, 0.5).name('FPS Speed');

        const marchFolder = gui.addFolder('Raymarcher');
        marchFolder.add(uniforms.u_maxSteps,  'value', 10,   500,  1   ).name('Max Steps');
        marchFolder.add(uniforms.u_maxDist,   'value', 10,   2000, 10  ).name('Max Distance');
        marchFolder.add(uniforms.u_hitThresh, 'value', 0.00001, 0.01   ).name('Hit Threshold');

        const lightFolder = gui.addFolder('Lighting');
        lightFolder.add(uniforms.u_diffIntensity,    'value', 0, 2,   0.01).name('Diffuse');
        lightFolder.add(uniforms.u_specIntensity,    'value', 0, 10,  0.1 ).name('Specular');
        lightFolder.add(uniforms.u_ambientIntensity, 'value', 0, 1,   0.01).name('Ambient');
        lightFolder.add(uniforms.u_shininess,        'value', 1, 128, 1   ).name('Shininess');

        

        // Make the panel draggable by its title bar
        const guiEl   = gui.domElement;
        const titleEl = guiEl.querySelector('.title');
        guiEl.style.position = 'fixed';
        guiEl.style.top      = '0px';
        guiEl.style.left     = (window.innerWidth - guiEl.offsetWidth - 16) + 'px';
        guiEl.style.right    = 'auto';
        titleEl.style.cursor = 'grab';

        let dragging = false, dragOffX = 0, dragOffY = 0;
        titleEl.addEventListener('mousedown', (e) => {
            dragging = true;
            const rect = guiEl.getBoundingClientRect();
            dragOffX = e.clientX - rect.left;
            dragOffY = e.clientY - rect.top;
            titleEl.style.cursor = 'grabbing';
        });
        document.addEventListener('mousemove', (e) => {
            if (!dragging) return;
            guiEl.style.left = (e.clientX - dragOffX) + 'px';
            guiEl.style.top  = (e.clientY - dragOffY) + 'px';
        });
        document.addEventListener('mouseup', () => {
            dragging = false;
            titleEl.style.cursor = 'grab';
        });

        // Raymarching plane
        const geometry = new three.PlaneGeometry();
        const material = new three.ShaderMaterial({
            vertexShader:   vert,
            fragmentShader: frag,
            uniforms:       uniforms,
        });

        // Camera near plane dimensions
        const nearPlaneWidth  = camera.near * Math.tan(three.MathUtils.degToRad(camera.fov / 2)) * camera.aspect * 2;
        const nearPlaneHeight = nearPlaneWidth / camera.aspect;

        const rayMarchPlane = new three.Mesh(geometry, material);
        rayMarchPlane.position.set(0, 0, -camera.near);
        rayMarchPlane.scale.set(nearPlaneWidth, nearPlaneHeight, 1);

        // Parent plane to camera so it tracks automatically 
        scene.add(camera);
        camera.add(rayMarchPlane);

        //reset camera with button and keybind
        function resetCamera() {
            orbit.enableDamping = false;
            orbit.update();
            orbit.reset();
            orbit.enableDamping = true;
            orbit.enableZoom = false;
            setTimeout(() => { orbit.enableZoom = true; }, 500);
        }
        document.getElementById('reset').addEventListener('click', resetCamera);
        window.addEventListener('keydown', (e) => { if (e.key === 'h' || e.key === 'H') resetCamera(); });
        

        const clock = new three.Clock();
        const startTime = performance.now();

        function render() {
            requestAnimationFrame(render);
            const delta = clock.getDelta();

            if (isFirstPerson && fp.isLocked) {
                if (keys.w) fp.moveForward( params.moveSpeed * delta);
                if (keys.s) fp.moveForward(-params.moveSpeed * delta);
                if (keys.d) fp.moveRight(  params.moveSpeed * delta);
                if (keys.a) fp.moveRight(  -params.moveSpeed * delta);
                if (keys.e) camera.position.y += params.moveSpeed * delta;
                if (keys.q) camera.position.y -= params.moveSpeed * delta;
            } else {
                orbit.update();
            }
            uniforms.u_time.value = (performance.now() - startTime) / 1000;

            renderer.render(scene, camera);
        }
        render();