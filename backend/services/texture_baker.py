"""
Texture Baking Service

Projects captured images onto mesh surface to create UV-mapped textures.

Pipeline:
1. UV Unwrapping (xatlas)
2. View selection (best images per face)
3. Texture projection
4. Seam blending
5. PBR material generation
"""

import asyncio
from pathlib import Path
from typing import Optional, Callable, Any
from dataclasses import dataclass
import numpy as np

from services.sugar_mesh import MeshData
from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class TextureConfig:
    """Configuration for texture baking"""
    # UV Atlas
    atlas_resolution: int = 4096
    atlas_padding: int = 4
    max_charts: int = 0  # 0 = automatic

    # View selection
    min_view_angle: float = 15.0  # degrees
    max_views_per_face: int = 3

    # Blending
    blend_seams: bool = True
    blend_radius: int = 4

    # Output
    generate_normal_map: bool = True
    generate_roughness_map: bool = True


@dataclass
class TexturedMesh:
    """Mesh with textures"""
    mesh: MeshData
    diffuse_texture: np.ndarray      # (H, W, 3) RGB
    normal_texture: Optional[np.ndarray]     # (H, W, 3) RGB
    roughness_texture: Optional[np.ndarray]  # (H, W, 1) grayscale
    uv_coords: np.ndarray            # (N, 2) per-vertex UVs


class TextureBaker:
    """
    Texture baking from multi-view images.

    Pipeline:
    1. Generate UV atlas using xatlas
    2. For each texel, find best source views
    3. Project and blend colors from multiple views
    4. Post-process: seam blending, inpainting
    5. Generate PBR maps (normal, roughness)
    """

    def __init__(self, config: TextureConfig = None):
        self.config = config or TextureConfig()

    async def bake_textures(
        self,
        mesh: MeshData,
        images_dir: Path,
        camera_poses: Optional[list],
        output_dir: Path,
        resolution: int = 4096,
        progress_callback: Optional[Callable[[float, str], Any]] = None
    ) -> dict:
        """
        Bake textures onto mesh from captured images.

        Args:
            mesh: Input mesh data
            images_dir: Directory with source images
            camera_poses: Camera pose for each image
            output_dir: Output directory
            resolution: Texture resolution (square)
            progress_callback: Progress callback

        Returns:
            Dict with textured mesh and file paths
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        self.config.atlas_resolution = resolution

        logger.info(f"Starting texture baking at {resolution}x{resolution}")

        try:
            # =================================================================
            # Step 1: UV Unwrapping
            # =================================================================
            if progress_callback:
                await progress_callback(0.0, "Generating UV atlas")

            uv_coords, charts = await self._generate_uv_atlas(mesh)

            logger.info(f"Generated UV atlas with {len(charts)} charts")

            # =================================================================
            # Step 2: Load Source Images
            # =================================================================
            if progress_callback:
                await progress_callback(0.15, "Loading source images")

            images, cameras = await self._load_source_images(images_dir, camera_poses)

            logger.info(f"Loaded {len(images)} source images")

            # =================================================================
            # Step 3: View Selection
            # =================================================================
            if progress_callback:
                await progress_callback(0.25, "Selecting best views per face")

            face_views = await self._select_views(
                mesh, cameras,
                progress_callback=lambda p: progress_callback(0.25 + p * 0.15, "Selecting views")
                if progress_callback else None
            )

            # =================================================================
            # Step 4: Texture Projection
            # =================================================================
            if progress_callback:
                await progress_callback(0.4, "Projecting textures")

            diffuse_texture = await self._project_textures(
                mesh, uv_coords, images, cameras, face_views,
                progress_callback=lambda p: progress_callback(0.4 + p * 0.35, "Projecting")
                if progress_callback else None
            )

            # =================================================================
            # Step 5: Seam Blending
            # =================================================================
            if self.config.blend_seams:
                if progress_callback:
                    await progress_callback(0.75, "Blending seams")

                diffuse_texture = await self._blend_seams(diffuse_texture, charts)

            # =================================================================
            # Step 6: Generate PBR Maps
            # =================================================================
            normal_texture = None
            roughness_texture = None

            if self.config.generate_normal_map:
                if progress_callback:
                    await progress_callback(0.85, "Generating normal map")
                normal_texture = await self._generate_normal_map(mesh, uv_coords)

            if self.config.generate_roughness_map:
                if progress_callback:
                    await progress_callback(0.9, "Generating roughness map")
                roughness_texture = await self._generate_roughness_map(diffuse_texture)

            # =================================================================
            # Step 7: Save Outputs
            # =================================================================
            if progress_callback:
                await progress_callback(0.95, "Saving textures")

            output_paths = await self._save_textures(
                output_dir,
                diffuse_texture,
                normal_texture,
                roughness_texture
            )

            # Update mesh with UVs
            textured_mesh = MeshData(
                vertices=mesh.vertices,
                faces=mesh.faces,
                normals=mesh.normals,
                uvs=uv_coords,
                colors=None
            )

            if progress_callback:
                await progress_callback(1.0, "Texture baking complete")

            return {
                "mesh": textured_mesh,
                "textures": output_paths,
                "vertex_count": len(mesh.vertices),
                "face_count": len(mesh.faces),
                "texture_resolution": resolution
            }

        except Exception as e:
            logger.error(f"Texture baking failed: {e}")
            raise

    async def _generate_uv_atlas(self, mesh: MeshData) -> tuple:
        """
        Generate UV atlas using xatlas algorithm.

        Returns:
            uv_coords: (N, 2) UV coordinates per vertex
            charts: List of chart info for seam detection
        """
        resolution = self.config.atlas_resolution

        # In production, use xatlas:
        # import xatlas
        # vmapping, indices, uvs = xatlas.parametrize(mesh.vertices, mesh.faces)

        # Placeholder: simple planar projection
        if len(mesh.vertices) == 0:
            return np.zeros((0, 2)), []

        vertices = mesh.vertices
        min_bound = vertices.min(axis=0)
        max_bound = vertices.max(axis=0)
        range_bound = max_bound - min_bound + 1e-6

        # Normalize to 0-1
        uv_coords = np.zeros((len(vertices), 2))
        uv_coords[:, 0] = (vertices[:, 0] - min_bound[0]) / range_bound[0]
        uv_coords[:, 1] = (vertices[:, 2] - min_bound[2]) / range_bound[2]

        charts = [{"id": 0, "faces": list(range(len(mesh.faces)))}]

        return uv_coords, charts

    async def _load_source_images(
        self,
        images_dir: Path,
        camera_poses: Optional[list]
    ) -> tuple:
        """Load source images and camera parameters"""

        images = []
        cameras = []

        if images_dir.exists():
            image_files = sorted(images_dir.glob("*.heic")) + \
                         sorted(images_dir.glob("*.jpg")) + \
                         sorted(images_dir.glob("*.png"))

            for i, img_path in enumerate(image_files):
                # Would load actual images here
                # from PIL import Image
                # img = np.array(Image.open(img_path))
                images.append({
                    "path": str(img_path),
                    "data": None  # Placeholder
                })

                if camera_poses and i < len(camera_poses):
                    cameras.append(camera_poses[i])
                else:
                    cameras.append(np.eye(4))  # Identity pose

        return images, cameras

    async def _select_views(
        self,
        mesh: MeshData,
        cameras: list,
        progress_callback: Optional[Callable] = None
    ) -> list:
        """
        Select best views for each face based on:
        1. Visibility (not occluded)
        2. View angle (face normal vs camera direction)
        3. Resolution (distance to camera)
        """
        face_views = []

        for face_idx, face in enumerate(mesh.faces):
            if progress_callback and face_idx % 1000 == 0:
                await progress_callback(face_idx / len(mesh.faces))

            # Get face center and normal
            v0, v1, v2 = mesh.vertices[face]
            face_center = (v0 + v1 + v2) / 3

            if mesh.normals is not None and len(mesh.normals) > 0:
                face_normal = (mesh.normals[face[0]] +
                              mesh.normals[face[1]] +
                              mesh.normals[face[2]]) / 3
                face_normal = face_normal / (np.linalg.norm(face_normal) + 1e-6)
            else:
                # Compute from cross product
                e1 = v1 - v0
                e2 = v2 - v0
                face_normal = np.cross(e1, e2)
                face_normal = face_normal / (np.linalg.norm(face_normal) + 1e-6)

            # Score each view
            view_scores = []

            for cam_idx, camera in enumerate(cameras):
                # Camera position (assuming 4x4 transform)
                cam_pos = camera[:3, 3] if camera.shape == (4, 4) else np.zeros(3)
                view_dir = cam_pos - face_center
                distance = np.linalg.norm(view_dir)

                if distance < 0.01:
                    continue

                view_dir = view_dir / distance

                # Angle between face normal and view direction
                cos_angle = np.dot(face_normal, view_dir)

                # Skip if facing away
                if cos_angle < np.cos(np.radians(90 - self.config.min_view_angle)):
                    continue

                # Score: prefer frontal views at medium distance
                score = cos_angle * (1.0 / (distance + 0.1))
                view_scores.append((cam_idx, score))

            # Sort by score and take top K
            view_scores.sort(key=lambda x: x[1], reverse=True)
            selected = [v[0] for v in view_scores[:self.config.max_views_per_face]]

            face_views.append(selected)

            if face_idx % 100 == 0:
                await asyncio.sleep(0)

        return face_views

    async def _project_textures(
        self,
        mesh: MeshData,
        uv_coords: np.ndarray,
        images: list,
        cameras: list,
        face_views: list,
        progress_callback: Optional[Callable] = None
    ) -> np.ndarray:
        """
        Project textures from source images to UV atlas.

        For each texel:
        1. Find corresponding 3D position on mesh
        2. Project to selected camera views
        3. Sample and blend colors
        """
        resolution = self.config.atlas_resolution

        # Initialize output texture
        texture = np.zeros((resolution, resolution, 3), dtype=np.float32)
        weights = np.zeros((resolution, resolution), dtype=np.float32)

        # Rasterize each face to texture
        for face_idx, face in enumerate(mesh.faces):
            if progress_callback and face_idx % 100 == 0:
                await progress_callback(face_idx / len(mesh.faces))

            # Get UVs for this face
            uv0, uv1, uv2 = uv_coords[face]

            # Get 3D positions
            v0, v1, v2 = mesh.vertices[face]

            # Get selected views
            views = face_views[face_idx] if face_idx < len(face_views) else []

            # Rasterize triangle in UV space
            # (Simplified - production would use proper rasterization)
            min_u = int(min(uv0[0], uv1[0], uv2[0]) * resolution)
            max_u = int(max(uv0[0], uv1[0], uv2[0]) * resolution) + 1
            min_v = int(min(uv0[1], uv1[1], uv2[1]) * resolution)
            max_v = int(max(uv0[1], uv1[1], uv2[1]) * resolution) + 1

            min_u = max(0, min_u)
            max_u = min(resolution, max_u)
            min_v = max(0, min_v)
            max_v = min(resolution, max_v)

            # Fill texels (simplified - just average vertex colors)
            if len(views) > 0:
                # Placeholder: gray texture
                for u in range(min_u, max_u):
                    for v in range(min_v, max_v):
                        texture[v, u] = [0.5, 0.5, 0.5]
                        weights[v, u] = 1.0

            if face_idx % 100 == 0:
                await asyncio.sleep(0)

        # Normalize by weights
        mask = weights > 0
        texture[mask] = texture[mask] / weights[mask, np.newaxis]

        # Fill holes (inpainting)
        texture = await self._inpaint_holes(texture, weights)

        return (texture * 255).astype(np.uint8)

    async def _blend_seams(
        self,
        texture: np.ndarray,
        charts: list
    ) -> np.ndarray:
        """
        Blend seams between UV charts using Poisson blending.
        """
        # In production, use OpenCV seamlessClone or custom Poisson solver

        # Placeholder: simple blur along seam edges
        return texture

    async def _generate_normal_map(
        self,
        mesh: MeshData,
        uv_coords: np.ndarray
    ) -> np.ndarray:
        """
        Generate tangent-space normal map from mesh geometry.
        """
        resolution = self.config.atlas_resolution

        # Placeholder: flat normal map (pointing up in tangent space)
        normal_map = np.zeros((resolution, resolution, 3), dtype=np.uint8)
        normal_map[:, :] = [128, 128, 255]  # (0, 0, 1) in tangent space

        return normal_map

    async def _generate_roughness_map(
        self,
        diffuse_texture: np.ndarray
    ) -> np.ndarray:
        """
        Estimate roughness from diffuse texture.
        High frequency detail → lower roughness (shinier)
        """
        resolution = self.config.atlas_resolution

        # Placeholder: medium roughness everywhere
        roughness_map = np.ones((resolution, resolution), dtype=np.uint8) * 128

        return roughness_map

    async def _inpaint_holes(
        self,
        texture: np.ndarray,
        weights: np.ndarray
    ) -> np.ndarray:
        """Inpaint unfilled regions in texture"""

        # In production, use OpenCV inpaint:
        # mask = (weights == 0).astype(np.uint8) * 255
        # texture = cv2.inpaint(texture, mask, 3, cv2.INPAINT_TELEA)

        return texture

    async def _save_textures(
        self,
        output_dir: Path,
        diffuse: np.ndarray,
        normal: Optional[np.ndarray],
        roughness: Optional[np.ndarray]
    ) -> dict:
        """Save texture files"""

        paths = {}

        # In production, use PIL or imageio:
        # Image.fromarray(diffuse).save(output_dir / "diffuse.png")

        diffuse_path = output_dir / "diffuse.png"
        diffuse_path.touch()
        paths["diffuse"] = str(diffuse_path)

        if normal is not None:
            normal_path = output_dir / "normal.png"
            normal_path.touch()
            paths["normal"] = str(normal_path)

        if roughness is not None:
            roughness_path = output_dir / "roughness.png"
            roughness_path.touch()
            paths["roughness"] = str(roughness_path)

        logger.info(f"Saved textures to {output_dir}")

        return paths
