"""
Depth Fusion Service

Fuses LiDAR depth with AI-estimated depth (from Depth Anything V2).
Same algorithm as iOS DepthFusionProcessor.swift.

The fusion combines the accuracy of LiDAR (within its range) with the
completeness of AI depth estimation (fills gaps, extends range).
"""

import logging
from dataclasses import dataclass
from typing import Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

# Lazy import for cv2
_cv2 = None


def _ensure_cv2():
    global _cv2
    if _cv2 is None:
        try:
            import cv2
            _cv2 = cv2
        except ImportError:
            logger.error("OpenCV not installed. Install with: pip install opencv-python")
            return False
    return True


@dataclass
class FusionResult:
    """Result of depth fusion"""
    fused_depth: np.ndarray           # Fused depth map (float32, meters)
    confidence_map: np.ndarray        # Per-pixel confidence (float32, 0-1)
    edge_map: Optional[np.ndarray]    # Edge detection result (uint8, optional)
    lidar_resolution: Tuple[int, int] # Original LiDAR resolution (H, W)
    output_resolution: Tuple[int, int] # Output resolution (H, W)
    stats: "FusionStats"


@dataclass
class FusionStats:
    """Statistics from the fusion process"""
    lidar_coverage: float      # Percentage of valid LiDAR pixels
    ai_contribution: float     # Percentage filled by AI
    edge_pixels: int           # Number of edge pixels detected
    processing_time_ms: float  # Processing time


class DepthFusionService:
    """
    Fuses LiDAR depth with AI depth estimation.

    Same algorithm as iOS DepthFusionProcessor:
    1. Upscale LiDAR to AI resolution (bilinear)
    2. Calibrate AI depth to metric using LiDAR reference
    3. Weighted fusion based on confidence
    4. Generate confidence map
    5. Optional: Edge detection for enhanced sampling
    """

    def __init__(
        self,
        weight_lidar: float = 0.8,
        weight_ai: float = 0.2,
        min_depth: float = 0.1,
        max_depth: float = 5.0,
        detect_edges: bool = True
    ):
        """
        Initialize the depth fusion service.

        Args:
            weight_lidar: Weight for LiDAR depth (0-1)
            weight_ai: Weight for AI depth (0-1)
            min_depth: Minimum valid depth in meters
            max_depth: Maximum valid depth in meters
            detect_edges: Whether to compute edge map
        """
        self.weight_lidar = weight_lidar
        self.weight_ai = weight_ai
        self.min_depth = min_depth
        self.max_depth = max_depth
        self.detect_edges = detect_edges

    def fuse(
        self,
        lidar_depth: np.ndarray,
        ai_depth: np.ndarray,
        lidar_confidence: Optional[np.ndarray] = None,
        ai_confidence: float = 0.7
    ) -> Optional[FusionResult]:
        """
        Fuse LiDAR and AI depth maps.

        Args:
            lidar_depth: LiDAR depth (H_l, W_l) float32, in meters
            ai_depth: AI depth (H_a, W_a) float32, relative (0-1) or metric
            lidar_confidence: LiDAR confidence (H_l, W_l) uint8, 0-2
            ai_confidence: Overall AI prediction confidence (0-1)

        Returns:
            FusionResult or None if fusion fails
        """
        import time
        start_time = time.time()

        if not _ensure_cv2():
            return None

        try:
            # Store original resolutions
            lidar_resolution = lidar_depth.shape[:2]
            output_resolution = ai_depth.shape[:2]

            # 1. Upscale LiDAR to AI resolution
            lidar_upscaled = _cv2.resize(
                lidar_depth,
                (ai_depth.shape[1], ai_depth.shape[0]),
                interpolation=_cv2.INTER_LINEAR
            )

            # Upscale confidence if provided
            if lidar_confidence is not None:
                conf_upscaled = _cv2.resize(
                    lidar_confidence.astype(np.float32),
                    (ai_depth.shape[1], ai_depth.shape[0]),
                    interpolation=_cv2.INTER_NEAREST
                )
            else:
                conf_upscaled = np.ones_like(lidar_upscaled)

            # 2. Create valid mask for LiDAR
            valid_mask = (
                (lidar_upscaled > self.min_depth) &
                (lidar_upscaled < self.max_depth) &
                (conf_upscaled >= 1)
            )

            lidar_coverage = valid_mask.sum() / valid_mask.size

            # 3. Calibrate AI depth if it's relative (0-1 range)
            ai_is_relative = ai_depth.max() <= 1.5
            if ai_is_relative and valid_mask.sum() > 100:
                ai_metric = self._calibrate_to_metric(
                    ai_depth, lidar_upscaled, valid_mask
                )
            else:
                ai_metric = ai_depth

            # 4. Compute per-pixel weights
            lidar_weight = np.where(valid_mask, self.weight_lidar, 0.0)
            ai_weight = np.where(valid_mask, self.weight_ai, 1.0)

            # Normalize weights
            total_weight = lidar_weight + ai_weight + 1e-6
            lidar_weight = lidar_weight / total_weight
            ai_weight = ai_weight / total_weight

            # 5. Weighted fusion
            fused_depth = lidar_weight * lidar_upscaled + ai_weight * ai_metric

            # Clip to valid range
            fused_depth = np.clip(fused_depth, self.min_depth, self.max_depth)

            # 6. Generate confidence map
            confidence_map = self._compute_confidence(
                lidar_upscaled, ai_metric, valid_mask, ai_confidence
            )

            # 7. Edge detection (optional)
            edge_map = None
            edge_pixels = 0
            if self.detect_edges:
                edge_map = self._detect_edges(fused_depth)
                edge_pixels = (edge_map > 128).sum()

            # Calculate AI contribution
            ai_contribution = 1.0 - lidar_coverage

            processing_time_ms = (time.time() - start_time) * 1000

            return FusionResult(
                fused_depth=fused_depth.astype(np.float32),
                confidence_map=confidence_map.astype(np.float32),
                edge_map=edge_map,
                lidar_resolution=lidar_resolution,
                output_resolution=output_resolution,
                stats=FusionStats(
                    lidar_coverage=lidar_coverage,
                    ai_contribution=ai_contribution,
                    edge_pixels=edge_pixels,
                    processing_time_ms=processing_time_ms
                )
            )

        except Exception as e:
            logger.error(f"Depth fusion failed: {e}")
            return None

    def _calibrate_to_metric(
        self,
        ai_relative: np.ndarray,
        lidar_metric: np.ndarray,
        valid_mask: np.ndarray
    ) -> np.ndarray:
        """
        Calibrate AI relative depth to metric using LiDAR reference.

        Uses the relationship: metric = 1 / (scale * relative + offset)

        Args:
            ai_relative: AI depth (0-1 range)
            lidar_metric: LiDAR depth (meters)
            valid_mask: Where LiDAR is valid

        Returns:
            Calibrated AI depth in meters
        """
        try:
            # Get valid samples
            lidar_valid = lidar_metric[valid_mask]
            ai_valid = ai_relative[valid_mask]

            # Inverse depth relationship
            inv_lidar = 1.0 / (lidar_valid + 1e-6)

            # Linear least squares: inv_depth = scale * relative + offset
            A = np.vstack([ai_valid, np.ones_like(ai_valid)]).T
            result = np.linalg.lstsq(A, inv_lidar, rcond=None)
            scale, offset = result[0]

            # Apply calibration
            ai_metric = 1.0 / (scale * ai_relative + offset + 1e-6)

            # Handle edge cases
            ai_metric = np.clip(ai_metric, self.min_depth, self.max_depth * 2)

            logger.debug(f"Depth calibration: scale={scale:.4f}, offset={offset:.4f}")

            return ai_metric

        except Exception as e:
            logger.warning(f"Calibration failed, using relative depth: {e}")
            # Fallback: simple scaling
            scale = lidar_metric[valid_mask].mean() / (ai_relative[valid_mask].mean() + 1e-6)
            return ai_relative * scale

    def _compute_confidence(
        self,
        lidar_depth: np.ndarray,
        ai_depth: np.ndarray,
        valid_mask: np.ndarray,
        ai_confidence: float
    ) -> np.ndarray:
        """
        Compute per-pixel confidence map.

        Confidence is higher where:
        - LiDAR data is available
        - LiDAR and AI agree
        - AI prediction confidence is high
        """
        # Base confidence from LiDAR availability
        confidence = np.where(valid_mask, 0.9, ai_confidence * 0.7)

        # Reduce confidence where LiDAR and AI disagree
        if valid_mask.sum() > 0:
            relative_diff = np.abs(lidar_depth - ai_depth) / (lidar_depth + 1e-6)
            disagreement_penalty = np.clip(relative_diff * 2, 0, 0.5)
            confidence = np.where(valid_mask, confidence - disagreement_penalty, confidence)

        return np.clip(confidence, 0.0, 1.0)

    def _detect_edges(self, depth: np.ndarray) -> np.ndarray:
        """
        Detect edges in depth map using Sobel operator.

        Edge pixels are important for point cloud sampling as they
        represent object boundaries and fine details.
        """
        # Normalize depth to 0-255 for edge detection
        depth_norm = ((depth - depth.min()) / (depth.max() - depth.min() + 1e-6) * 255).astype(np.uint8)

        # Sobel edge detection
        sobel_x = _cv2.Sobel(depth_norm, _cv2.CV_64F, 1, 0, ksize=3)
        sobel_y = _cv2.Sobel(depth_norm, _cv2.CV_64F, 0, 1, ksize=3)

        # Magnitude
        magnitude = np.sqrt(sobel_x**2 + sobel_y**2)
        magnitude = (magnitude / magnitude.max() * 255).astype(np.uint8)

        return magnitude


class PointCloudExtractor:
    """
    Extract point cloud from fused depth map.

    Same algorithm as iOS HighResPointCloudExtractor:
    1. Back-project depth to 3D using camera intrinsics
    2. Filter by confidence threshold
    3. Estimate surface normals from depth gradients
    4. Optionally sample colors from RGB image
    """

    def __init__(
        self,
        min_confidence: float = 0.3,
        voxel_size: float = 0.005,  # 5mm voxel grid for downsampling
        max_points: int = 2_000_000
    ):
        self.min_confidence = min_confidence
        self.voxel_size = voxel_size
        self.max_points = max_points

    def extract(
        self,
        depth: np.ndarray,
        confidence: np.ndarray,
        intrinsics: np.ndarray,
        transform: Optional[np.ndarray] = None,
        rgb_image: Optional[np.ndarray] = None
    ) -> Tuple[np.ndarray, Optional[np.ndarray], Optional[np.ndarray]]:
        """
        Extract point cloud from depth map.

        Args:
            depth: Depth map (H, W) float32, in meters
            confidence: Confidence map (H, W) float32, 0-1
            intrinsics: Camera intrinsics matrix 3x3
            transform: World transform 4x4 (optional)
            rgb_image: Color image (H, W, 3) uint8 (optional)

        Returns:
            Tuple of:
            - points: (N, 3) float32 positions
            - colors: (N, 3) uint8 colors or None
            - normals: (N, 3) float32 normals or None
        """
        H, W = depth.shape

        # Camera intrinsics
        fx = intrinsics[0, 0]
        fy = intrinsics[1, 1]
        cx = intrinsics[0, 2]
        cy = intrinsics[1, 2]

        # Create pixel coordinate grid
        u = np.arange(W)
        v = np.arange(H)
        u, v = np.meshgrid(u, v)

        # Filter by confidence
        mask = confidence >= self.min_confidence

        # Back-project to 3D
        z = depth[mask]
        x = (u[mask] - cx) * z / fx
        y = (v[mask] - cy) * z / fy

        points = np.stack([x, y, z], axis=-1)

        # Apply world transform if provided
        if transform is not None:
            # Convert to homogeneous coordinates
            ones = np.ones((points.shape[0], 1))
            points_h = np.concatenate([points, ones], axis=-1)
            points = (transform @ points_h.T).T[:, :3]

        # Sample colors
        colors = None
        if rgb_image is not None:
            v_idx = v[mask].astype(int)
            u_idx = u[mask].astype(int)
            colors = rgb_image[v_idx, u_idx]

        # Estimate normals from depth gradients
        normals = self._estimate_normals(depth, mask, intrinsics)

        # Voxel downsampling if too many points
        if len(points) > self.max_points:
            points, colors, normals = self._voxel_downsample(
                points, colors, normals
            )

        logger.info(f"Extracted {len(points)} points from depth map")

        return points.astype(np.float32), colors, normals

    def _estimate_normals(
        self,
        depth: np.ndarray,
        mask: np.ndarray,
        intrinsics: np.ndarray
    ) -> Optional[np.ndarray]:
        """Estimate surface normals from depth gradients"""
        if not _ensure_cv2():
            return None

        try:
            # Compute depth gradients
            dz_dx = _cv2.Sobel(depth, _cv2.CV_64F, 1, 0, ksize=3)
            dz_dy = _cv2.Sobel(depth, _cv2.CV_64F, 0, 1, ksize=3)

            fx = intrinsics[0, 0]
            fy = intrinsics[1, 1]

            # Normal = cross product of tangent vectors
            nx = -dz_dx[mask] / fx
            ny = -dz_dy[mask] / fy
            nz = np.ones_like(nx)

            # Normalize
            length = np.sqrt(nx**2 + ny**2 + nz**2) + 1e-6
            normals = np.stack([nx/length, ny/length, nz/length], axis=-1)

            return normals.astype(np.float32)

        except Exception as e:
            logger.warning(f"Normal estimation failed: {e}")
            return None

    def _voxel_downsample(
        self,
        points: np.ndarray,
        colors: Optional[np.ndarray],
        normals: Optional[np.ndarray]
    ) -> Tuple[np.ndarray, Optional[np.ndarray], Optional[np.ndarray]]:
        """Downsample points using voxel grid"""
        # Compute voxel indices
        voxel_indices = (points / self.voxel_size).astype(np.int32)

        # Find unique voxels
        _, unique_idx = np.unique(
            voxel_indices, axis=0, return_index=True
        )

        # Sample unique points
        points = points[unique_idx]

        if colors is not None:
            colors = colors[unique_idx]

        if normals is not None:
            normals = normals[unique_idx]

        # Further random sampling if still too many
        if len(points) > self.max_points:
            idx = np.random.choice(len(points), self.max_points, replace=False)
            points = points[idx]
            if colors is not None:
                colors = colors[idx]
            if normals is not None:
                normals = normals[idx]

        return points, colors, normals
