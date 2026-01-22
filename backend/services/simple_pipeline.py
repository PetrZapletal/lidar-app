"""
Simple Processing Pipeline for Apple Silicon (MPS/CPU)

Simplified 3D reconstruction pipeline that bypasses Gaussian Splatting
(which requires CUDA) and instead uses:

1. Parse LRAW → mesh anchors, textures, depths
2. AI Depth Enhancement (Depth Anything V2)
3. Point Cloud Extraction
4. Poisson Surface Reconstruction (Open3D)
5. Export (PLY, GLB, OBJ)
"""

import asyncio
from pathlib import Path
from typing import Optional, Callable, Any
from dataclasses import dataclass

import numpy as np

from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class PipelineProgress:
    """Progress information for pipeline stages"""
    progress: float  # 0.0 - 1.0
    stage: str
    message: str


@dataclass
class PipelineResult:
    """Result of pipeline processing"""
    status: str  # "success" or "error"
    pointcloud_path: Optional[str] = None
    mesh_path: Optional[str] = None
    exports: Optional[dict] = None
    stats: Optional[dict] = None
    error: Optional[str] = None


class SimplePipeline:
    """
    Simplified processing pipeline for Apple Silicon.

    Stages:
    1. Parse LRAW (10%)
    2. AI Depth Enhancement (30%)
    3. Point Cloud Extraction (20%)
    4. Poisson Reconstruction (30%)
    5. Export (10%)
    """

    STAGES = [
        ("parsing", 0.0, 0.1, "Parsing LRAW data"),
        ("ai_depth", 0.1, 0.4, "Running AI depth enhancement"),
        ("pointcloud", 0.4, 0.6, "Generating point cloud"),
        ("mesh", 0.6, 0.9, "Reconstructing mesh"),
        ("export", 0.9, 1.0, "Exporting formats"),
    ]

    def __init__(self, output_dir: str = "/data/scans/processed"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Lazy load services
        self._raw_processor = None
        self._depth_service = None
        self._fusion_service = None

    def _ensure_services(self):
        """Lazy load processing services"""
        if self._raw_processor is None:
            from services.raw_data_processor import RawDataProcessor
            self._raw_processor = RawDataProcessor(str(self.output_dir))

        try:
            if self._depth_service is None:
                from services.depth_anything import get_depth_anything_service
                self._depth_service = get_depth_anything_service()

            if self._fusion_service is None:
                from services.depth_fusion import DepthFusionService
                self._fusion_service = DepthFusionService()

            return True
        except Exception as e:
            logger.warning(f"AI services not available: {e}")
            return False

    async def process(
        self,
        scan_id: str,
        lraw_path: str,
        progress_callback: Optional[Callable[[float, str, str], Any]] = None
    ) -> PipelineResult:
        """
        Process scan through simplified pipeline.

        Args:
            scan_id: Unique scan identifier
            lraw_path: Path to LRAW file
            progress_callback: Optional callback(progress, stage, message)

        Returns:
            PipelineResult with paths to generated files
        """
        output_path = self.output_dir / scan_id
        output_path.mkdir(parents=True, exist_ok=True)

        self._ensure_services()

        try:
            # Stage 1: Parse LRAW
            await self._report_progress(progress_callback, 0.0, "parsing", "Parsing LRAW data...")
            lraw_data = self._raw_processor.parse_lraw(Path(lraw_path))

            logger.info(
                f"Parsed LRAW: {len(lraw_data.mesh_anchors)} meshes, "
                f"{len(lraw_data.texture_frames)} textures, "
                f"{len(lraw_data.depth_frames)} depth frames"
            )

            # Stage 2: AI Depth Enhancement
            await self._report_progress(progress_callback, 0.1, "ai_depth", "Running AI depth enhancement...")
            enhanced_result = await self._raw_processor._enhance_depth_with_ai(lraw_data, output_path)

            # Stage 3: Point Cloud Generation
            await self._report_progress(progress_callback, 0.4, "pointcloud", "Generating point cloud...")

            if enhanced_result and "enhanced_pointcloud_path" in enhanced_result:
                pc_path = Path(enhanced_result["enhanced_pointcloud_path"])
                logger.info(f"Using AI-enhanced point cloud: {pc_path}")
            else:
                # Fallback to mesh-based point cloud
                pc_path = await self._raw_processor._extract_pointcloud(lraw_data, output_path)
                logger.info(f"Using mesh-based point cloud: {pc_path}")

            # Stage 4: Poisson Reconstruction
            await self._report_progress(progress_callback, 0.6, "mesh", "Reconstructing mesh...")
            mesh_path = await self._poisson_reconstruction(pc_path, output_path)

            # Stage 5: Export
            await self._report_progress(progress_callback, 0.9, "export", "Exporting formats...")
            exports = await self._export_formats(mesh_path, pc_path, output_path)

            await self._report_progress(progress_callback, 1.0, "completed", "Processing complete")

            return PipelineResult(
                status="success",
                pointcloud_path=str(pc_path),
                mesh_path=str(mesh_path),
                exports=exports,
                stats={
                    "mesh_anchors": len(lraw_data.mesh_anchors),
                    "texture_frames": len(lraw_data.texture_frames),
                    "depth_frames": len(lraw_data.depth_frames),
                    "total_vertices": lraw_data.total_vertices,
                    "total_faces": lraw_data.total_faces,
                    "ai_enhanced": enhanced_result is not None
                }
            )

        except Exception as e:
            logger.error(f"Pipeline failed: {e}")
            import traceback
            traceback.print_exc()

            return PipelineResult(
                status="error",
                error=str(e)
            )

    async def _report_progress(
        self,
        callback: Optional[Callable],
        progress: float,
        stage: str,
        message: str
    ):
        """Report progress to callback if available"""
        if callback:
            try:
                result = callback(progress, stage, message)
                if asyncio.iscoroutine(result):
                    await result
            except Exception as e:
                logger.warning(f"Progress callback failed: {e}")

        logger.debug(f"Pipeline progress: {progress:.0%} - {stage}: {message}")

    async def _poisson_reconstruction(self, pc_path: Path, output_path: Path) -> Path:
        """
        Poisson surface reconstruction using Open3D.

        Args:
            pc_path: Path to input point cloud PLY
            output_path: Directory for output

        Returns:
            Path to reconstructed mesh PLY
        """
        try:
            import open3d as o3d
        except ImportError:
            logger.error("Open3D not installed, skipping mesh reconstruction")
            return pc_path  # Return point cloud as fallback

        mesh_path = output_path / "mesh.ply"

        # Load point cloud
        logger.info(f"Loading point cloud from {pc_path}")
        pcd = o3d.io.read_point_cloud(str(pc_path))

        point_count = len(pcd.points)
        if point_count == 0:
            logger.warning("Empty point cloud, creating minimal mesh")
            mesh = o3d.geometry.TriangleMesh()
            o3d.io.write_triangle_mesh(str(mesh_path), mesh)
            return mesh_path

        logger.info(f"Point cloud has {point_count} points")

        # Filter out points with extreme coordinates (garbage data)
        points = np.asarray(pcd.points)
        valid_mask = np.all(np.isfinite(points), axis=1) & np.all(np.abs(points) < 1000, axis=1)
        if not np.all(valid_mask):
            invalid_count = np.sum(~valid_mask)
            logger.warning(f"Removing {invalid_count} points with invalid coordinates")
            pcd = pcd.select_by_index(np.where(valid_mask)[0])
            point_count = len(pcd.points)
            logger.info(f"Point cloud now has {point_count} points after filtering")

        if point_count < 10:
            logger.error(f"Too few valid points ({point_count}) for mesh reconstruction")
            mesh = o3d.geometry.TriangleMesh()
            o3d.io.write_triangle_mesh(str(mesh_path), mesh)
            return mesh_path

        # Remove statistical outliers
        logger.info("Removing statistical outliers...")
        try:
            pcd, ind = pcd.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)
            logger.info(f"After outlier removal: {len(pcd.points)} points")
        except Exception as e:
            logger.warning(f"Outlier removal failed: {e}")

        # Estimate normals if missing
        if not pcd.has_normals():
            logger.info("Estimating normals...")
            pcd.estimate_normals(
                search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=0.1, max_nn=30)
            )

        # Orient normals consistently
        try:
            logger.info("Orienting normals...")
            pcd.orient_normals_consistent_tangent_plane(k=15)
        except Exception as e:
            logger.warning(f"Normal orientation failed: {e}")
            # Try simpler orientation
            try:
                pcd.orient_normals_towards_camera_location(camera_location=np.array([0, 0, 0]))
            except:
                pass

        # Poisson reconstruction
        logger.info("Running Poisson reconstruction (depth=9)...")
        try:
            mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(
                pcd, depth=9, width=0, scale=1.1, linear_fit=False
            )
        except Exception as e:
            logger.error(f"Poisson reconstruction failed: {e}")
            # Try with lower depth
            logger.info("Retrying with depth=7...")
            mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(
                pcd, depth=7
            )

        # Remove low-density vertices (trim the mesh)
        densities = np.asarray(densities)
        if len(densities) > 0:
            threshold = np.quantile(densities, 0.01)
            vertices_to_remove = densities < threshold
            mesh.remove_vertices_by_mask(vertices_to_remove)
            logger.info(f"Removed {vertices_to_remove.sum()} low-density vertices")

        # Clean mesh
        mesh.remove_degenerate_triangles()
        mesh.remove_duplicated_vertices()
        mesh.remove_duplicated_triangles()
        mesh.remove_non_manifold_edges()

        # Compute normals for the mesh
        mesh.compute_vertex_normals()

        # Save mesh
        o3d.io.write_triangle_mesh(str(mesh_path), mesh)

        vertex_count = len(mesh.vertices)
        face_count = len(mesh.triangles)
        logger.info(f"Created mesh: {vertex_count} vertices, {face_count} faces")

        return mesh_path

    async def _export_formats(
        self,
        mesh_path: Path,
        pc_path: Path,
        output_path: Path
    ) -> dict:
        """
        Export to multiple formats (GLB, OBJ).

        Args:
            mesh_path: Path to mesh PLY
            pc_path: Path to point cloud PLY
            output_path: Output directory

        Returns:
            Dict of format -> path mappings
        """
        exports = {"ply": str(pc_path)}

        try:
            import trimesh

            # Load mesh
            mesh = trimesh.load(str(mesh_path))

            if mesh.is_empty:
                logger.warning("Mesh is empty, skipping GLB/OBJ export")
                return exports

            # GLB export (binary glTF)
            try:
                glb_path = output_path / "model.glb"
                mesh.export(str(glb_path), file_type='glb')
                exports["glb"] = str(glb_path)
                logger.info(f"Exported GLB: {glb_path}")
            except Exception as e:
                logger.warning(f"GLB export failed: {e}")

            # OBJ export
            try:
                obj_path = output_path / "model.obj"
                mesh.export(str(obj_path), file_type='obj')
                exports["obj"] = str(obj_path)
                logger.info(f"Exported OBJ: {obj_path}")
            except Exception as e:
                logger.warning(f"OBJ export failed: {e}")

        except ImportError:
            logger.warning("trimesh not installed, skipping GLB/OBJ export")
        except Exception as e:
            logger.error(f"Export failed: {e}")

        return exports


# Singleton instance for convenience
_pipeline_instance = None


def get_simple_pipeline() -> SimplePipeline:
    """Get or create SimplePipeline instance"""
    global _pipeline_instance
    if _pipeline_instance is None:
        _pipeline_instance = SimplePipeline()
    return _pipeline_instance
