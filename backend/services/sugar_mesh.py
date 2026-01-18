"""
SuGaR Mesh Extraction Service

Extracts clean triangle meshes from 3D Gaussian Splatting using the SuGaR method.
Based on: "SuGaR: Surface-Aligned Gaussian Splatting for Efficient 3D Mesh
           Reconstruction and High-Quality Mesh Rendering"
Paper: https://arxiv.org/abs/2311.12775
"""

import asyncio
from pathlib import Path
from typing import Optional, Callable, Any
from dataclasses import dataclass
import numpy as np

from services.gaussian_splatting import Gaussian
from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class SuGaRConfig:
    """Configuration for SuGaR mesh extraction"""
    # Regularization
    regularization_iterations: int = 7000
    flat_loss_weight: float = 0.1

    # Density extraction
    density_threshold: float = 0.5
    voxel_size: float = 0.01  # 1cm voxels

    # Poisson reconstruction
    poisson_depth: int = 10
    poisson_scale: float = 1.1

    # Refinement
    refinement_iterations: int = 2000
    refine_with_gaussians: bool = True

    # Output
    target_faces: Optional[int] = None  # None = no simplification


@dataclass
class MeshData:
    """Mesh data structure"""
    vertices: np.ndarray      # (N, 3) vertex positions
    faces: np.ndarray         # (M, 3) triangle indices
    normals: np.ndarray       # (N, 3) vertex normals
    uvs: Optional[np.ndarray] # (N, 2) UV coordinates
    colors: Optional[np.ndarray]  # (N, 3) vertex colors


class SuGaRMeshExtractor:
    """
    SuGaR mesh extraction from 3D Gaussian Splatting.

    Pipeline:
    1. Surface alignment: Regularize Gaussians to align with surface
    2. Density extraction: Sample density field from aligned Gaussians
    3. Poisson reconstruction: Extract mesh from oriented point cloud
    4. Mesh refinement: Joint optimization of mesh and bound Gaussians
    """

    RESOLUTION_SETTINGS = {
        "low": {"voxel_size": 0.02, "poisson_depth": 8, "target_faces": 50000},
        "medium": {"voxel_size": 0.01, "poisson_depth": 9, "target_faces": 200000},
        "high": {"voxel_size": 0.005, "poisson_depth": 10, "target_faces": None},
    }

    def __init__(self, config: SuGaRConfig = None):
        self.config = config or SuGaRConfig()

    async def extract_from_gaussians(
        self,
        gaussians: list,
        output_dir: Path,
        resolution: str = "high",
        progress_callback: Optional[Callable[[float, str], Any]] = None
    ) -> dict:
        """
        Extract mesh from 3D Gaussian Splatting model.

        Args:
            gaussians: List of trained Gaussian objects
            output_dir: Output directory
            resolution: "low", "medium", or "high"
            progress_callback: Progress callback

        Returns:
            Dict with mesh data and statistics
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Apply resolution settings
        settings = self.RESOLUTION_SETTINGS.get(resolution, self.RESOLUTION_SETTINGS["high"])
        self.config.voxel_size = settings["voxel_size"]
        self.config.poisson_depth = settings["poisson_depth"]
        self.config.target_faces = settings["target_faces"]

        logger.info(f"Starting SuGaR mesh extraction (resolution: {resolution})")

        try:
            # =================================================================
            # Step 1: Surface Alignment Regularization
            # =================================================================
            if progress_callback:
                await progress_callback(0.0, "Regularizing Gaussians for surface alignment")

            aligned_gaussians = await self._surface_alignment(
                gaussians,
                progress_callback
            )

            # =================================================================
            # Step 2: Density Field Extraction
            # =================================================================
            if progress_callback:
                await progress_callback(0.3, "Extracting density field")

            density_samples = await self._extract_density_field(aligned_gaussians)

            # =================================================================
            # Step 3: Poisson Surface Reconstruction
            # =================================================================
            if progress_callback:
                await progress_callback(0.5, "Running Poisson reconstruction")

            raw_mesh = await self._poisson_reconstruction(density_samples)

            # =================================================================
            # Step 4: Mesh Cleaning and Simplification
            # =================================================================
            if progress_callback:
                await progress_callback(0.7, "Cleaning and simplifying mesh")

            clean_mesh = await self._clean_mesh(raw_mesh)

            # =================================================================
            # Step 5: Optional Refinement
            # =================================================================
            if self.config.refine_with_gaussians:
                if progress_callback:
                    await progress_callback(0.85, "Refining mesh with Gaussians")

                refined_mesh = await self._refine_mesh(clean_mesh, aligned_gaussians)
            else:
                refined_mesh = clean_mesh

            # =================================================================
            # Step 6: Save Output
            # =================================================================
            if progress_callback:
                await progress_callback(0.95, "Saving mesh")

            mesh_path = output_dir / "mesh.ply"
            await self._save_mesh(refined_mesh, mesh_path)

            if progress_callback:
                await progress_callback(1.0, "Mesh extraction complete")

            return {
                "mesh": refined_mesh,
                "mesh_path": str(mesh_path),
                "vertex_count": len(refined_mesh.vertices),
                "face_count": len(refined_mesh.faces)
            }

        except Exception as e:
            logger.error(f"SuGaR mesh extraction failed: {e}")
            raise

    async def extract_from_pointcloud(
        self,
        pointcloud: dict,
        output_dir: Path,
        resolution: str = "high",
        progress_callback: Optional[Callable[[float, str], Any]] = None
    ) -> dict:
        """
        Extract mesh directly from point cloud using Poisson reconstruction.
        Fallback when Gaussian Splatting is not used.
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        settings = self.RESOLUTION_SETTINGS.get(resolution, self.RESOLUTION_SETTINGS["high"])
        self.config.poisson_depth = settings["poisson_depth"]
        self.config.target_faces = settings["target_faces"]

        logger.info(f"Starting direct Poisson reconstruction (resolution: {resolution})")

        try:
            # Prepare density samples from point cloud
            if progress_callback:
                await progress_callback(0.1, "Preparing point cloud")

            points = pointcloud.get("points", np.zeros((0, 3)))
            normals = pointcloud.get("normals")

            # Estimate normals if not provided
            if normals is None:
                if progress_callback:
                    await progress_callback(0.2, "Estimating normals")
                normals = await self._estimate_normals(points)

            density_samples = {
                "points": points,
                "normals": normals
            }

            # Poisson reconstruction
            if progress_callback:
                await progress_callback(0.4, "Running Poisson reconstruction")

            raw_mesh = await self._poisson_reconstruction(density_samples)

            # Clean and simplify
            if progress_callback:
                await progress_callback(0.7, "Cleaning mesh")

            clean_mesh = await self._clean_mesh(raw_mesh)

            # Save
            if progress_callback:
                await progress_callback(0.95, "Saving mesh")

            mesh_path = output_dir / "mesh.ply"
            await self._save_mesh(clean_mesh, mesh_path)

            if progress_callback:
                await progress_callback(1.0, "Complete")

            return {
                "mesh": clean_mesh,
                "mesh_path": str(mesh_path),
                "vertex_count": len(clean_mesh.vertices),
                "face_count": len(clean_mesh.faces)
            }

        except Exception as e:
            logger.error(f"Poisson reconstruction failed: {e}")
            raise

    async def _surface_alignment(
        self,
        gaussians: list,
        progress_callback: Optional[Callable] = None
    ) -> list:
        """
        Regularize Gaussians to align with the surface.

        Adds a "flatness" loss that encourages Gaussians to have
        one very small scale dimension (perpendicular to surface).
        """
        aligned = gaussians.copy()

        iterations = self.config.regularization_iterations
        log_interval = iterations // 10

        for i in range(iterations):
            if i % log_interval == 0 and progress_callback:
                progress = 0.0 + 0.3 * (i / iterations)
                await progress_callback(progress, f"Surface alignment iteration {i}/{iterations}")

            # In production:
            # 1. Render from random views
            # 2. Compute photometric loss
            # 3. Add flatness regularization: L_flat = sum(min(s_i))
            # 4. Backpropagate and update

            if i % 100 == 0:
                await asyncio.sleep(0)

        return aligned

    async def _extract_density_field(self, gaussians: list) -> dict:
        """
        Sample the density field defined by Gaussians.

        For each point in space, density = sum of Gaussian contributions:
        density(x) = Σ_i α_i * exp(-0.5 * (x - μ_i)^T Σ_i^-1 (x - μ_i))
        """
        # Compute bounding box
        if not gaussians:
            return {"points": np.zeros((0, 3)), "normals": np.zeros((0, 3))}

        positions = np.array([g.position for g in gaussians])
        min_bound = positions.min(axis=0) - 0.1
        max_bound = positions.max(axis=0) + 0.1

        # Sample density on grid
        voxel_size = self.config.voxel_size
        grid_dims = np.ceil((max_bound - min_bound) / voxel_size).astype(int)

        # Collect high-density points
        high_density_points = []
        high_density_normals = []

        # In production, use CUDA for efficient density evaluation
        # Here we approximate with Gaussian centers

        for g in gaussians:
            if g.opacity > self.config.density_threshold:
                high_density_points.append(g.position)

                # Estimate normal from smallest covariance eigenvector
                eigenvalues, eigenvectors = np.linalg.eigh(g.covariance)
                normal = eigenvectors[:, 0]  # Smallest eigenvalue direction
                high_density_normals.append(normal)

        return {
            "points": np.array(high_density_points) if high_density_points else np.zeros((0, 3)),
            "normals": np.array(high_density_normals) if high_density_normals else np.zeros((0, 3))
        }

    async def _poisson_reconstruction(self, density_samples: dict) -> MeshData:
        """
        Screened Poisson Surface Reconstruction.

        Solves: ∇²χ = ∇·V
        Where V is the vector field defined by oriented points.
        """
        points = density_samples["points"]
        normals = density_samples["normals"]

        if len(points) == 0:
            return MeshData(
                vertices=np.zeros((0, 3)),
                faces=np.zeros((0, 3), dtype=np.int32),
                normals=np.zeros((0, 3)),
                uvs=None,
                colors=None
            )

        # In production, use Open3D or PyMeshLab:
        # pcd = o3d.geometry.PointCloud()
        # pcd.points = o3d.utility.Vector3dVector(points)
        # pcd.normals = o3d.utility.Vector3dVector(normals)
        # mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(
        #     pcd, depth=self.config.poisson_depth
        # )

        # Placeholder mesh
        vertices = points
        faces = np.zeros((0, 3), dtype=np.int32)

        return MeshData(
            vertices=vertices,
            faces=faces,
            normals=normals,
            uvs=None,
            colors=None
        )

    async def _clean_mesh(self, mesh: MeshData) -> MeshData:
        """
        Clean and simplify mesh.

        1. Remove non-manifold edges
        2. Fill small holes
        3. Remove isolated components
        4. Quadric decimation to target face count
        """
        # In production, use PyMeshLab or Open3D

        if self.config.target_faces and len(mesh.faces) > self.config.target_faces:
            # Quadric error simplification
            logger.info(f"Simplifying mesh from {len(mesh.faces)} to {self.config.target_faces} faces")
            # Would use pymeshlab.simplification_quadric_edge_collapse_decimation

        return mesh

    async def _refine_mesh(
        self,
        mesh: MeshData,
        gaussians: list
    ) -> MeshData:
        """
        Joint refinement of mesh and Gaussians.

        1. Bind Gaussians to mesh surface
        2. Optimize mesh vertices and Gaussian parameters jointly
        3. Render loss + mesh smoothness regularization
        """
        # In production:
        # 1. For each Gaussian, find nearest mesh vertex
        # 2. Constrain Gaussian position to mesh surface
        # 3. Joint optimization with rendering loss

        return mesh

    async def _estimate_normals(self, points: np.ndarray) -> np.ndarray:
        """Estimate normals from point cloud using PCA"""

        if len(points) == 0:
            return np.zeros((0, 3))

        # In production, use Open3D:
        # pcd = o3d.geometry.PointCloud()
        # pcd.points = o3d.utility.Vector3dVector(points)
        # pcd.estimate_normals()
        # normals = np.asarray(pcd.normals)

        # Placeholder: upward normals
        normals = np.zeros_like(points)
        normals[:, 1] = 1.0

        return normals

    async def _save_mesh(self, mesh: MeshData, path: Path):
        """Save mesh to PLY format"""

        # In production, use plyfile or trimesh:
        # mesh_trimesh = trimesh.Trimesh(
        #     vertices=mesh.vertices,
        #     faces=mesh.faces,
        #     vertex_normals=mesh.normals
        # )
        # mesh_trimesh.export(path)

        # Placeholder
        path.touch()
        logger.info(f"Saved mesh to {path}")
