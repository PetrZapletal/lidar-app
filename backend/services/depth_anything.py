"""
Depth Anything V2 Service

PyTorch implementation of the same model used on iOS (CoreML).
Uses HuggingFace transformers for easy model loading.

This enables server-side depth estimation with the same quality as edge processing.
"""

import logging
from typing import Optional, Tuple
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

# Lazy imports for optional dependencies
_torch = None
_transforms = None
_Image = None


def _ensure_imports():
    """Lazy import torch and related libraries"""
    global _torch, _transforms, _Image

    if _torch is None:
        try:
            import torch
            _torch = torch
        except ImportError:
            logger.warning("PyTorch not installed. Depth Anything will use fallback mode.")
            return False

    if _transforms is None:
        try:
            from transformers import AutoModelForDepthEstimation, AutoImageProcessor
            _transforms = {
                "AutoModelForDepthEstimation": AutoModelForDepthEstimation,
                "AutoImageProcessor": AutoImageProcessor
            }
        except ImportError:
            logger.warning("Transformers not installed. Depth Anything will use fallback mode.")
            return False

    if _Image is None:
        try:
            from PIL import Image
            _Image = Image
        except ImportError:
            logger.warning("PIL not installed.")
            return False

    return True


class DepthAnythingService:
    """
    Depth Anything V2 monocular depth estimation.

    Same model as iOS CoreML version (DepthAnythingV2SmallF16.mlpackage),
    but using PyTorch for server-side inference.

    Model: depth-anything/Depth-Anything-V2-Small-hf
    Input: RGB image (any size, internally resized to 518x518)
    Output: Relative depth map (0-1), same aspect ratio as input
    """

    MODEL_ID = "depth-anything/Depth-Anything-V2-Small-hf"

    def __init__(self, device: Optional[str] = None, cache_dir: Optional[str] = None):
        """
        Initialize the Depth Anything V2 model.

        Args:
            device: "cuda", "mps", "cpu", or None for auto-detect
            cache_dir: Directory to cache downloaded model
        """
        self.model = None
        self.processor = None
        self.device = device
        self.cache_dir = cache_dir
        self._is_loaded = False

    def load_model(self) -> bool:
        """
        Load the model from HuggingFace Hub.

        Returns:
            True if model loaded successfully, False otherwise
        """
        if self._is_loaded:
            return True

        if not _ensure_imports():
            logger.error("Required dependencies not available")
            return False

        try:
            logger.info(f"Loading Depth Anything V2 model: {self.MODEL_ID}")

            # Load processor and model
            self.processor = _transforms["AutoImageProcessor"].from_pretrained(
                self.MODEL_ID,
                cache_dir=self.cache_dir
            )

            self.model = _transforms["AutoModelForDepthEstimation"].from_pretrained(
                self.MODEL_ID,
                cache_dir=self.cache_dir
            )

            # Auto-detect device
            if self.device is None:
                if _torch.cuda.is_available():
                    self.device = "cuda"
                elif hasattr(_torch.backends, "mps") and _torch.backends.mps.is_available():
                    self.device = "mps"
                else:
                    self.device = "cpu"

            logger.info(f"Using device: {self.device}")

            # Move model to device
            self.model = self.model.to(self.device)
            self.model.eval()

            self._is_loaded = True
            logger.info("Depth Anything V2 model loaded successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to load Depth Anything model: {e}")
            return False

    @property
    def is_loaded(self) -> bool:
        """Check if model is loaded and ready"""
        return self._is_loaded

    def predict(self, rgb_image: np.ndarray) -> Optional[np.ndarray]:
        """
        Predict depth from RGB image.

        Args:
            rgb_image: RGB image as numpy array (H, W, 3) uint8

        Returns:
            Relative depth map (H', W') float32, values 0-1
            None if prediction fails
        """
        if not self._is_loaded:
            if not self.load_model():
                logger.error("Model not loaded and could not be loaded")
                return None

        try:
            # Convert numpy to PIL Image
            pil_image = _Image.fromarray(rgb_image)

            # Preprocess
            inputs = self.processor(images=pil_image, return_tensors="pt")
            inputs = {k: v.to(self.device) for k, v in inputs.items()}

            # Inference
            with _torch.no_grad():
                outputs = self.model(**inputs)
                predicted_depth = outputs.predicted_depth

            # Post-process: squeeze batch dim and convert to numpy
            depth = predicted_depth.squeeze().cpu().numpy()

            # Normalize to 0-1 range
            depth_min = depth.min()
            depth_max = depth.max()
            if depth_max - depth_min > 1e-6:
                depth = (depth - depth_min) / (depth_max - depth_min)
            else:
                depth = np.zeros_like(depth)

            return depth.astype(np.float32)

        except Exception as e:
            logger.error(f"Depth prediction failed: {e}")
            return None

    def predict_metric_depth(
        self,
        rgb_image: np.ndarray,
        lidar_depth: Optional[np.ndarray] = None,
        lidar_confidence: Optional[np.ndarray] = None
    ) -> Tuple[Optional[np.ndarray], Optional[np.ndarray], float]:
        """
        Predict metric depth by calibrating against LiDAR.

        Same approach as iOS DepthAnythingModel.predictMetricDepth().

        Args:
            rgb_image: RGB image (H, W, 3) uint8
            lidar_depth: LiDAR depth map (H', W') float32, in meters
            lidar_confidence: LiDAR confidence (H', W') uint8, 0-2

        Returns:
            Tuple of:
            - relative_depth: Relative depth (0-1)
            - metric_depth: Calibrated metric depth in meters (or None)
            - confidence: Overall confidence score (0-1)
        """
        # Get relative depth
        relative_depth = self.predict(rgb_image)
        if relative_depth is None:
            return None, None, 0.0

        # If no LiDAR reference, return only relative
        if lidar_depth is None:
            return relative_depth, None, 0.5

        try:
            import cv2

            # Resize LiDAR to match AI depth resolution
            lidar_resized = cv2.resize(
                lidar_depth,
                (relative_depth.shape[1], relative_depth.shape[0]),
                interpolation=cv2.INTER_LINEAR
            )

            # Create valid mask (LiDAR depth in valid range)
            valid_mask = (lidar_resized > 0.1) & (lidar_resized < 5.0)

            if lidar_confidence is not None:
                conf_resized = cv2.resize(
                    lidar_confidence.astype(np.float32),
                    (relative_depth.shape[1], relative_depth.shape[0]),
                    interpolation=cv2.INTER_NEAREST
                )
                valid_mask = valid_mask & (conf_resized >= 1)

            valid_count = valid_mask.sum()

            if valid_count < 100:
                logger.warning(f"Insufficient LiDAR points for calibration: {valid_count}")
                return relative_depth, None, 0.3

            # Calibrate: metric = 1 / (scale * relative + offset)
            # Use least squares fitting
            lidar_valid = lidar_resized[valid_mask]
            relative_valid = relative_depth[valid_mask]

            # Inverse relationship: 1/metric = scale * relative + offset
            inv_lidar = 1.0 / (lidar_valid + 1e-6)

            # Linear fit
            A = np.vstack([relative_valid, np.ones_like(relative_valid)]).T
            result = np.linalg.lstsq(A, inv_lidar, rcond=None)
            scale, offset = result[0]

            # Apply calibration
            metric_depth = 1.0 / (scale * relative_depth + offset + 1e-6)

            # Clip to valid range
            metric_depth = np.clip(metric_depth, 0.1, 10.0)

            # Compute confidence based on fit quality
            residuals = result[1]
            if len(residuals) > 0:
                rmse = np.sqrt(residuals[0] / valid_count)
                confidence = max(0.0, min(1.0, 1.0 - rmse * 2))
            else:
                confidence = 0.7

            logger.debug(f"Calibration: scale={scale:.4f}, offset={offset:.4f}, confidence={confidence:.2f}")

            return relative_depth, metric_depth.astype(np.float32), confidence

        except Exception as e:
            logger.error(f"Metric depth calibration failed: {e}")
            return relative_depth, None, 0.3

    def unload_model(self):
        """Unload model to free memory"""
        if self.model is not None:
            del self.model
            self.model = None

        if self.processor is not None:
            del self.processor
            self.processor = None

        self._is_loaded = False

        # Try to free GPU memory
        if _torch is not None and _torch.cuda.is_available():
            _torch.cuda.empty_cache()

        logger.info("Depth Anything model unloaded")


# Singleton instance for reuse
_depth_anything_instance: Optional[DepthAnythingService] = None


def get_depth_anything_service(
    device: Optional[str] = None,
    cache_dir: Optional[str] = None
) -> DepthAnythingService:
    """
    Get or create the Depth Anything service singleton.

    Args:
        device: Device to use ("cuda", "mps", "cpu")
        cache_dir: Model cache directory

    Returns:
        DepthAnythingService instance
    """
    global _depth_anything_instance

    if _depth_anything_instance is None:
        _depth_anything_instance = DepthAnythingService(
            device=device,
            cache_dir=cache_dir
        )

    return _depth_anything_instance
