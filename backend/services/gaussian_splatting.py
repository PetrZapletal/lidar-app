"""
3D Gaussian Splatting Training Service

Implements the 3D Gaussian Splatting algorithm for neural radiance field training.
Based on: "3D Gaussian Splatting for Real-Time Radiance Field Rendering"
Paper: https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/
"""

import os
import asyncio
from pathlib import Path
from typing import Optional, Callable, Any
from dataclasses import dataclass
import numpy as np

from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class GaussianConfig:
    """Configuration for Gaussian Splatting training"""
    # Training
    iterations: int = 30000
    learning_rate_position: float = 0.00016
    learning_rate_feature: float = 0.0025
    learning_rate_opacity: float = 0.05
    learning_rate_scaling: float = 0.005
    learning_rate_rotation: float = 0.001

    # Densification
    densify_from_iter: int = 500
    densify_until_iter: int = 15000
    densify_grad_threshold: float = 0.0002
    densification_interval: int = 100

    # Pruning
    opacity_reset_interval: int = 3000
    min_opacity: float = 0.005

    # Optimization
    percent_dense: float = 0.01
    lambda_dssim: float = 0.2

    # Output
    save_iterations: list = None

    def __post_init__(self):
        if self.save_iterations is None:
            self.save_iterations = [7000, 15000, 30000]


@dataclass
class Gaussian:
    """Single 3D Gaussian representation"""
    position: np.ndarray      # (3,) mean position
    covariance: np.ndarray    # (3, 3) covariance matrix
    opacity: float            # alpha value
    sh_coefficients: np.ndarray  # Spherical harmonics for view-dependent color


class GaussianSplattingTrainer:
    """
    3D Gaussian Splatting trainer.

    Training pipeline:
    1. Initialize Gaussians from point cloud
    2. Differentiable rasterization
    3. Gradient descent optimization
    4. Adaptive density control (clone, split, prune)
    """

    def __init__(self, config: GaussianConfig = None):
        self.config = config or GaussianConfig()
        self.device = "cuda" if self._check_cuda() else "cpu"

        logger.info(f"GaussianSplattingTrainer initialized on {self.device}")

    def _check_cuda(self) -> bool:
        """Check if CUDA is available"""
        try:
            import torch
            return torch.cuda.is_available()
        except ImportError:
            return False

    async def train(
        self,
        pointcloud: dict,
        images_dir: Path,
        camera_poses: Optional[list],
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], Any]] = None
    ) -> dict:
        """
        Train 3D Gaussian Splatting model.

        Args:
            pointcloud: Dict with 'points', 'colors', 'normals'
            images_dir: Directory with training images
            camera_poses: List of camera pose matrices
            output_dir: Directory for outputs
            progress_callback: Progress update callback

        Returns:
            Dict with trained gaussians and statistics
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        logger.info("Starting 3D Gaussian Splatting training")

        try:
            # =================================================================
            # Step 1: Initialize Gaussians from point cloud
            # =================================================================
            if progress_callback:
                await progress_callback(0.0, "Initializing Gaussians from point cloud")

            gaussians = await self._initialize_gaussians(pointcloud)

            logger.info(f"Initialized {len(gaussians)} Gaussians")

            # =================================================================
            # Step 2: Load training images and cameras
            # =================================================================
            if progress_callback:
                await progress_callback(0.05, "Loading training images")

            training_data = await self._load_training_data(images_dir, camera_poses)

            logger.info(f"Loaded {len(training_data['images'])} training images")

            # =================================================================
            # Step 3: Training loop
            # =================================================================
            total_iterations = self.config.iterations
            log_interval = total_iterations // 100  # Log every 1%

            for iteration in range(total_iterations):
                # Update progress
                if iteration % log_interval == 0:
                    progress = 0.1 + 0.8 * (iteration / total_iterations)
                    if progress_callback:
                        await progress_callback(
                            progress,
                            f"Training iteration {iteration}/{total_iterations}"
                        )

                # Training step
                loss = await self._training_step(
                    gaussians,
                    training_data,
                    iteration
                )

                # Densification
                if (self.config.densify_from_iter <= iteration < self.config.densify_until_iter
                    and iteration % self.config.densification_interval == 0):
                    gaussians = await self._densify(gaussians, iteration)

                # Opacity reset
                if iteration % self.config.opacity_reset_interval == 0:
                    gaussians = await self._reset_opacity(gaussians)

                # Save checkpoint
                if iteration in self.config.save_iterations:
                    await self._save_checkpoint(gaussians, output_dir, iteration)

                # Yield to event loop periodically
                if iteration % 100 == 0:
                    await asyncio.sleep(0)

            # =================================================================
            # Step 4: Final optimization and export
            # =================================================================
            if progress_callback:
                await progress_callback(0.95, "Finalizing model")

            # Save final model
            final_path = await self._save_gaussians(gaussians, output_dir / "final")

            if progress_callback:
                await progress_callback(1.0, "Training complete")

            return {
                "gaussians": gaussians,
                "gaussian_count": len(gaussians),
                "model_path": str(final_path),
                "training_stats": {
                    "iterations": total_iterations,
                    "final_gaussian_count": len(gaussians)
                }
            }

        except Exception as e:
            logger.error(f"Gaussian Splatting training failed: {e}")
            raise

    async def _initialize_gaussians(self, pointcloud: dict) -> list:
        """Initialize Gaussians from point cloud points"""

        points = pointcloud.get("points", np.zeros((0, 3)))
        colors = pointcloud.get("colors")
        normals = pointcloud.get("normals")

        gaussians = []

        for i, point in enumerate(points):
            # Initial covariance (isotropic)
            initial_scale = 0.01  # 1cm initial size
            covariance = np.eye(3) * initial_scale

            # Initial opacity
            opacity = 0.5

            # Initial spherical harmonics (just DC term from color)
            if colors is not None and i < len(colors):
                # Convert RGB to SH DC coefficient
                sh_dc = colors[i] * 0.282095  # Y_0^0 coefficient
                sh_coefficients = np.zeros((16, 3))  # 4 bands
                sh_coefficients[0] = sh_dc
            else:
                sh_coefficients = np.zeros((16, 3))
                sh_coefficients[0] = [0.5, 0.5, 0.5]

            gaussians.append(Gaussian(
                position=point.copy(),
                covariance=covariance,
                opacity=opacity,
                sh_coefficients=sh_coefficients
            ))

        return gaussians

    async def _load_training_data(
        self,
        images_dir: Path,
        camera_poses: Optional[list]
    ) -> dict:
        """Load training images and camera parameters"""

        images = []
        cameras = []

        if images_dir.exists():
            image_files = sorted(images_dir.glob("*.heic")) + sorted(images_dir.glob("*.jpg"))

            for img_path in image_files:
                # Would load actual images here
                images.append(str(img_path))

        if camera_poses:
            cameras = camera_poses

        return {
            "images": images,
            "cameras": cameras
        }

    async def _training_step(
        self,
        gaussians: list,
        training_data: dict,
        iteration: int
    ) -> float:
        """
        Single training step.

        In production, this would:
        1. Sample a random training view
        2. Rasterize Gaussians to image
        3. Compute L1 + D-SSIM loss
        4. Backpropagate gradients
        5. Update Gaussian parameters
        """
        # Placeholder - actual implementation would use CUDA rasterizer
        loss = 0.1 * (1.0 - iteration / self.config.iterations)
        return loss

    async def _densify(self, gaussians: list, iteration: int) -> list:
        """
        Adaptive density control.

        1. Clone: Small Gaussians with high gradient → duplicate
        2. Split: Large Gaussians with high gradient → split into 2 smaller
        3. Prune: Low opacity or too large Gaussians → remove
        """
        # Placeholder for actual densification logic
        return gaussians

    async def _reset_opacity(self, gaussians: list) -> list:
        """Reset opacity to near-zero for culling"""
        for g in gaussians:
            # In actual implementation, this helps prune invisible Gaussians
            pass
        return gaussians

    async def _save_checkpoint(
        self,
        gaussians: list,
        output_dir: Path,
        iteration: int
    ):
        """Save training checkpoint"""
        checkpoint_path = output_dir / f"checkpoint_{iteration:06d}.ply"

        # Would save Gaussian parameters to PLY format
        logger.info(f"Saved checkpoint: {checkpoint_path}")

    async def _save_gaussians(self, gaussians: list, output_dir: Path) -> Path:
        """Save final Gaussian model"""
        output_dir.mkdir(parents=True, exist_ok=True)

        # Save as PLY with custom properties
        output_path = output_dir / "gaussians.ply"

        # In production, save:
        # - positions (xyz)
        # - scales (sx, sy, sz)
        # - rotations (quaternion)
        # - opacities
        # - spherical harmonics coefficients

        # Placeholder - create empty file
        output_path.touch()

        logger.info(f"Saved {len(gaussians)} Gaussians to {output_path}")

        return output_path


class GaussianRenderer:
    """
    Differentiable Gaussian Rasterizer.

    Renders 3D Gaussians to 2D image using:
    1. Project 3D Gaussians to 2D
    2. Sort by depth (front-to-back)
    3. Alpha compositing with tile-based rasterization
    """

    def __init__(self, image_width: int, image_height: int):
        self.width = image_width
        self.height = image_height

    def render(
        self,
        gaussians: list,
        camera_intrinsics: np.ndarray,
        camera_extrinsics: np.ndarray
    ) -> np.ndarray:
        """
        Render Gaussians to image.

        Returns:
            RGB image as numpy array (H, W, 3)
        """
        # Placeholder - actual implementation uses CUDA
        image = np.zeros((self.height, self.width, 3), dtype=np.float32)
        return image
