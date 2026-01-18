"""
Scan Processing Pipeline

Orchestrates the full 3D reconstruction pipeline:
1. Point cloud preprocessing
2. 3D Gaussian Splatting training
3. SuGaR mesh extraction
4. Texture baking
5. Export to multiple formats
"""

import os
import asyncio
from pathlib import Path
from typing import Callable, Optional, Any
from dataclasses import dataclass

from services.gaussian_splatting import GaussianSplattingTrainer
from services.sugar_mesh import SuGaRMeshExtractor
from services.texture_baker import TextureBaker
from services.export_service import ModelExporter
from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class ProcessingStage:
    """Processing stage definition"""
    name: str
    weight: float  # Percentage of total progress
    description: str


class ScanProcessor:
    """
    Main processor for 3D scan reconstruction.

    Pipeline stages:
    1. Preprocessing (10%)    - Point cloud cleanup, normalization
    2. 3DGS Training (40%)    - Gaussian Splatting optimization
    3. Mesh Extraction (25%)  - SuGaR surface reconstruction
    4. Texture Baking (15%)   - UV mapping and texture projection
    5. Export (10%)           - Convert to output formats
    """

    STAGES = [
        ProcessingStage("preprocessing", 0.10, "Preprocessing point cloud"),
        ProcessingStage("gaussian_splatting", 0.40, "Training 3D Gaussian Splatting"),
        ProcessingStage("mesh_extraction", 0.25, "Extracting mesh with SuGaR"),
        ProcessingStage("texture_baking", 0.15, "Baking textures"),
        ProcessingStage("export", 0.10, "Exporting to formats"),
    ]

    def __init__(self, data_dir: str = "/data/scans"):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

        # Initialize sub-services
        self.gs_trainer = GaussianSplattingTrainer()
        self.mesh_extractor = SuGaRMeshExtractor()
        self.texture_baker = TextureBaker()
        self.exporter = ModelExporter()

    async def process_scan(
        self,
        scan_id: str,
        options: dict,
        progress_callback: Optional[Callable[[float, str, str], Any]] = None
    ) -> dict:
        """
        Process a scan through the full pipeline.

        Args:
            scan_id: Unique scan identifier
            options: Processing options
            progress_callback: Async callback for progress updates

        Returns:
            dict with output_urls for each format
        """
        scan_dir = self.data_dir / scan_id
        output_dir = scan_dir / "output"
        output_dir.mkdir(parents=True, exist_ok=True)

        logger.info(f"Starting processing for scan: {scan_id}")

        # Track overall progress
        current_progress = 0.0

        async def update_progress(stage_progress: float, stage: str, message: str = None):
            """Update progress within a stage"""
            stage_info = next((s for s in self.STAGES if s.name == stage), None)
            if stage_info:
                stage_idx = self.STAGES.index(stage_info)
                base_progress = sum(s.weight for s in self.STAGES[:stage_idx])
                nonlocal current_progress
                current_progress = base_progress + stage_progress * stage_info.weight

            if progress_callback:
                await progress_callback(current_progress, stage, message)

        try:
            # =================================================================
            # Stage 1: Preprocessing
            # =================================================================
            await update_progress(0.0, "preprocessing", "Loading point cloud")

            pointcloud_path = scan_dir / "pointcloud.ply"
            metadata_path = scan_dir / "metadata.json"
            textures_dir = scan_dir / "textures"

            # Preprocess point cloud
            preprocessed_data = await self._preprocess_pointcloud(
                pointcloud_path,
                metadata_path,
                progress_callback=lambda p, m: update_progress(p, "preprocessing", m)
            )

            await update_progress(1.0, "preprocessing", "Preprocessing complete")

            # =================================================================
            # Stage 2: 3D Gaussian Splatting
            # =================================================================
            if options.get("enable_gaussian_splatting", True):
                await update_progress(0.0, "gaussian_splatting", "Initializing Gaussians")

                gs_output = await self.gs_trainer.train(
                    pointcloud=preprocessed_data["pointcloud"],
                    images_dir=textures_dir,
                    camera_poses=preprocessed_data.get("camera_poses"),
                    output_dir=output_dir / "gaussian_splatting",
                    progress_callback=lambda p, m: update_progress(p, "gaussian_splatting", m)
                )

                await update_progress(1.0, "gaussian_splatting", "Gaussian Splatting complete")
            else:
                gs_output = None

            # =================================================================
            # Stage 3: Mesh Extraction
            # =================================================================
            if options.get("enable_mesh_extraction", True):
                await update_progress(0.0, "mesh_extraction", "Initializing SuGaR")

                resolution = options.get("mesh_resolution", "high")

                if gs_output:
                    # Extract mesh from Gaussian Splatting
                    mesh_output = await self.mesh_extractor.extract_from_gaussians(
                        gaussians=gs_output["gaussians"],
                        output_dir=output_dir / "mesh",
                        resolution=resolution,
                        progress_callback=lambda p, m: update_progress(p, "mesh_extraction", m)
                    )
                else:
                    # Direct mesh from point cloud (Poisson reconstruction)
                    mesh_output = await self.mesh_extractor.extract_from_pointcloud(
                        pointcloud=preprocessed_data["pointcloud"],
                        output_dir=output_dir / "mesh",
                        resolution=resolution,
                        progress_callback=lambda p, m: update_progress(p, "mesh_extraction", m)
                    )

                await update_progress(1.0, "mesh_extraction", "Mesh extraction complete")
            else:
                mesh_output = None

            # =================================================================
            # Stage 4: Texture Baking
            # =================================================================
            if options.get("enable_texture_baking", True) and mesh_output:
                await update_progress(0.0, "texture_baking", "UV unwrapping")

                texture_resolution = options.get("texture_resolution", 4096)

                textured_mesh = await self.texture_baker.bake_textures(
                    mesh=mesh_output["mesh"],
                    images_dir=textures_dir,
                    camera_poses=preprocessed_data.get("camera_poses"),
                    output_dir=output_dir / "textured",
                    resolution=texture_resolution,
                    progress_callback=lambda p, m: update_progress(p, "texture_baking", m)
                )

                await update_progress(1.0, "texture_baking", "Texture baking complete")
            else:
                textured_mesh = mesh_output

            # =================================================================
            # Stage 5: Export
            # =================================================================
            await update_progress(0.0, "export", "Starting export")

            output_formats = options.get("output_formats", ["usdz", "gltf", "obj"])
            output_urls = {}

            for i, fmt in enumerate(output_formats):
                await update_progress(i / len(output_formats), "export", f"Exporting {fmt.upper()}")

                output_path = await self.exporter.export(
                    mesh=textured_mesh["mesh"] if textured_mesh else None,
                    gaussians=gs_output["gaussians"] if gs_output else None,
                    format=fmt,
                    output_dir=output_dir / "exports"
                )

                output_urls[fmt] = str(output_path)

            await update_progress(1.0, "export", "Export complete")

            logger.info(f"Processing complete for scan: {scan_id}")

            return {
                "status": "success",
                "output_urls": output_urls,
                "stats": {
                    "vertex_count": textured_mesh.get("vertex_count") if textured_mesh else 0,
                    "face_count": textured_mesh.get("face_count") if textured_mesh else 0,
                    "gaussian_count": gs_output.get("gaussian_count") if gs_output else 0,
                }
            }

        except Exception as e:
            logger.error(f"Processing failed for scan {scan_id}: {e}")
            raise

    async def _preprocess_pointcloud(
        self,
        pointcloud_path: Path,
        metadata_path: Path,
        progress_callback: Optional[Callable] = None
    ) -> dict:
        """Preprocess point cloud data"""

        import numpy as np

        # Simulated preprocessing for now
        # In production, use Open3D or similar

        if progress_callback:
            await progress_callback(0.2, "Loading point cloud")

        # Load point cloud (placeholder)
        pointcloud_data = {
            "points": np.zeros((0, 3)),
            "colors": None,
            "normals": None
        }

        if pointcloud_path.exists():
            # Would use plyfile or open3d here
            pass

        if progress_callback:
            await progress_callback(0.5, "Removing outliers")

        # Statistical outlier removal
        # Would use open3d.geometry.PointCloud.remove_statistical_outlier()

        if progress_callback:
            await progress_callback(0.7, "Estimating normals")

        # Normal estimation
        # Would use open3d.geometry.PointCloud.estimate_normals()

        if progress_callback:
            await progress_callback(0.9, "Loading camera poses")

        # Load camera poses from metadata
        camera_poses = None
        if metadata_path.exists():
            import json
            with open(metadata_path) as f:
                metadata = json.load(f)
                camera_poses = metadata.get("camera_poses")

        if progress_callback:
            await progress_callback(1.0, "Preprocessing complete")

        return {
            "pointcloud": pointcloud_data,
            "camera_poses": camera_poses
        }
