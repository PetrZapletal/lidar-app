/**
 * Three.js Point Cloud Viewer
 *
 * Interactive 3D point cloud visualization for scan preview.
 * Supports orbit controls, zoom, and height-based coloring.
 */

// Import Three.js using import map (defined in HTML)
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

export class PointCloudViewer {
    constructor(container, scanId, options = {}) {
        this.container = typeof container === 'string'
            ? document.getElementById(container)
            : container;
        this.scanId = scanId;
        this.pointSize = options.pointSize || 2.0;
        this.colorMode = options.colorMode || 'height'; // 'height', 'rgb', 'distance'
        this.maxPoints = options.maxPoints || 100000;

        this.scene = null;
        this.camera = null;
        this.renderer = null;
        this.controls = null;
        this.pointCloud = null;
        this.originalData = null;

        this.init();
        this.loadPointCloud();
    }

    init() {
        // Scene
        this.scene = new THREE.Scene();
        this.scene.background = new THREE.Color(0x111827);

        // Camera
        const aspect = this.container.clientWidth / this.container.clientHeight;
        this.camera = new THREE.PerspectiveCamera(60, aspect, 0.01, 1000);
        this.camera.position.set(2, 2, 2);

        // Renderer
        this.renderer = new THREE.WebGLRenderer({
            antialias: true,
            alpha: false
        });
        this.renderer.setSize(this.container.clientWidth, this.container.clientHeight);
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        this.container.appendChild(this.renderer.domElement);

        // Controls
        this.controls = new OrbitControls(this.camera, this.renderer.domElement);
        this.controls.enableDamping = true;
        this.controls.dampingFactor = 0.05;
        this.controls.screenSpacePanning = true;
        this.controls.minDistance = 0.1;
        this.controls.maxDistance = 100;

        // Grid
        const grid = new THREE.GridHelper(10, 20, 0x444444, 0x222222);
        this.scene.add(grid);

        // Axes helper
        const axes = new THREE.AxesHelper(1);
        this.scene.add(axes);

        // Ambient light (for potential mesh rendering)
        const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
        this.scene.add(ambientLight);

        // Resize handler
        this._boundOnResize = () => this.onResize();
        window.addEventListener('resize', this._boundOnResize);

        // Start animation loop
        this.animate();
    }

    async loadPointCloud() {
        this.showLoading(true);

        try {
            const url = `/api/v1/debug/scans/${this.scanId}/pointcloud/preview?max_points=${this.maxPoints}`;
            const response = await fetch(url);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();

            if (data.points && data.points.length > 0) {
                this.originalData = data;
                this.createPointCloud(data.points, data.colors, data.bounds);
                this.updateStats(data.point_count);
            } else {
                this.showError('No point cloud data available');
            }

        } catch (error) {
            console.error('Failed to load point cloud:', error);
            this.showError(`Failed to load: ${error.message}`);
        } finally {
            this.showLoading(false);
        }
    }

    createPointCloud(points, colors, bounds) {
        // Remove existing point cloud
        if (this.pointCloud) {
            this.scene.remove(this.pointCloud);
            this.pointCloud.geometry.dispose();
            this.pointCloud.material.dispose();
        }

        const geometry = new THREE.BufferGeometry();

        // Positions
        const positions = new Float32Array(points.length * 3);
        for (let i = 0; i < points.length; i++) {
            positions[i * 3] = points[i][0];
            positions[i * 3 + 1] = points[i][1];
            positions[i * 3 + 2] = points[i][2];
        }
        geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

        // Colors
        const colorArray = this.computeColors(points, colors, bounds);
        geometry.setAttribute('color', new THREE.BufferAttribute(colorArray, 3));

        // Material
        const material = new THREE.PointsMaterial({
            size: this.pointSize * 0.01,
            vertexColors: true,
            sizeAttenuation: true,
            transparent: true,
            opacity: 0.9
        });

        // Create points
        this.pointCloud = new THREE.Points(geometry, material);
        this.scene.add(this.pointCloud);

        // Center camera on point cloud
        this.centerCamera(bounds);
    }

    computeColors(points, colors, bounds) {
        const colorArray = new Float32Array(points.length * 3);
        const minY = bounds.min[1];
        const maxY = bounds.max[1];
        const rangeY = maxY - minY || 1;

        for (let i = 0; i < points.length; i++) {
            let r, g, b;

            if (this.colorMode === 'rgb' && colors && colors[i]) {
                // Use provided RGB colors
                r = colors[i][0] / 255;
                g = colors[i][1] / 255;
                b = colors[i][2] / 255;
            } else if (this.colorMode === 'distance') {
                // Color by distance from origin
                const dist = Math.sqrt(
                    points[i][0] ** 2 +
                    points[i][1] ** 2 +
                    points[i][2] ** 2
                );
                const t = Math.min(dist / 5, 1); // Normalize to 5m
                [r, g, b] = this.turboColormap(t);
            } else {
                // Color by height (default)
                const t = (points[i][1] - minY) / rangeY;
                [r, g, b] = this.turboColormap(t);
            }

            colorArray[i * 3] = r;
            colorArray[i * 3 + 1] = g;
            colorArray[i * 3 + 2] = b;
        }

        return colorArray;
    }

    /**
     * Turbo colormap approximation
     * Maps value t (0-1) to RGB color
     */
    turboColormap(t) {
        // Simplified turbo colormap
        const r = Math.max(0, Math.min(1,
            0.13572138 + t * (4.61539260 + t * (-42.66032258 + t * (132.13108234 + t * (-152.94239396 + t * 59.28637943))))
        ));
        const g = Math.max(0, Math.min(1,
            0.09140261 + t * (2.19418839 + t * (4.84296658 + t * (-14.18503333 + t * (4.27729857 + t * 2.82956604))))
        ));
        const b = Math.max(0, Math.min(1,
            0.10667330 + t * (12.64194608 + t * (-60.58204836 + t * (110.36276771 + t * (-89.90310912 + t * 27.34824973))))
        ));
        return [r, g, b];
    }

    centerCamera(bounds) {
        const center = new THREE.Vector3(
            (bounds.min[0] + bounds.max[0]) / 2,
            (bounds.min[1] + bounds.max[1]) / 2,
            (bounds.min[2] + bounds.max[2]) / 2
        );

        const size = Math.max(
            bounds.max[0] - bounds.min[0],
            bounds.max[1] - bounds.min[1],
            bounds.max[2] - bounds.min[2]
        );

        // Position camera
        this.camera.position.set(
            center.x + size * 1.2,
            center.y + size * 0.8,
            center.z + size * 1.2
        );

        this.controls.target.copy(center);
        this.controls.update();
    }

    setPointSize(size) {
        this.pointSize = size;
        if (this.pointCloud) {
            this.pointCloud.material.size = size * 0.01;
        }
    }

    setColorMode(mode) {
        this.colorMode = mode;
        if (this.originalData) {
            const colorArray = this.computeColors(
                this.originalData.points,
                this.originalData.colors,
                this.originalData.bounds
            );
            this.pointCloud.geometry.setAttribute(
                'color',
                new THREE.BufferAttribute(colorArray, 3)
            );
        }
    }

    resetCamera() {
        if (this.originalData) {
            this.centerCamera(this.originalData.bounds);
        }
    }

    toggleFullscreen() {
        if (!document.fullscreenElement) {
            this.container.requestFullscreen().catch(err => {
                console.warn('Fullscreen request failed:', err);
            });
        } else {
            document.exitFullscreen();
        }
    }

    showLoading(show) {
        const loading = this.container.querySelector('#viewer-loading');
        if (loading) {
            loading.style.display = show ? 'flex' : 'none';
        }
    }

    showError(message) {
        const loading = this.container.querySelector('#viewer-loading');
        if (loading) {
            loading.innerHTML = `
                <div class="text-center text-red-400">
                    <i class="fas fa-exclamation-triangle text-4xl mb-2"></i>
                    <p>${message}</p>
                </div>
            `;
            loading.style.display = 'flex';
        }
    }

    updateStats(pointCount) {
        const stats = document.getElementById('point-count');
        if (stats) {
            stats.textContent = pointCount.toLocaleString();
        }
    }

    onResize() {
        if (!this.container || !this.camera || !this.renderer) return;

        const width = this.container.clientWidth;
        const height = this.container.clientHeight;

        this.camera.aspect = width / height;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(width, height);
    }

    animate() {
        if (!this.renderer) return;

        requestAnimationFrame(() => this.animate());
        this.controls.update();
        this.renderer.render(this.scene, this.camera);
    }

    dispose() {
        // Clean up
        window.removeEventListener('resize', this._boundOnResize);

        if (this.pointCloud) {
            this.pointCloud.geometry.dispose();
            this.pointCloud.material.dispose();
        }

        if (this.renderer) {
            this.renderer.dispose();
            this.container.removeChild(this.renderer.domElement);
        }

        this.scene = null;
        this.camera = null;
        this.renderer = null;
        this.controls = null;
    }
}

// Export for global access
window.PointCloudViewer = PointCloudViewer;
