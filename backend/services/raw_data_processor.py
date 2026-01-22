"""
Raw Data Processor

Parses and processes raw scan data uploaded via debug pipeline.
Converts iOS LRAW binary format into standard processing inputs.
"""

import struct
import numpy as np
from pathlib import Path
from typing import Optional, Callable, Awaitable, Any
from dataclasses import dataclass

from utils.logger import get_logger

logger = get_logger(__name__)

# Lazy imports for optional AI depth processing
_depth_anything_service = None
_depth_fusion_service = None


def _ensure_depth_services():
    """Lazy load depth processing services"""
    global _depth_anything_service, _depth_fusion_service

    if _depth_anything_service is None:
        try:
            from services.depth_anything import get_depth_anything_service
            from services.depth_fusion import DepthFusionService

            _depth_anything_service = get_depth_anything_service()
            _depth_fusion_service = DepthFusionService()
            logger.info("Depth AI services loaded successfully")
            return True
        except ImportError as e:
            logger.warning(f"Depth AI services not available: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to load depth AI services: {e}")
            return False

    return True


@dataclass
class MeshAnchorData:
    """Parsed mesh anchor from LRAW format"""
    uuid: bytes
    transform: np.ndarray  # 4x4 float32
    vertices: np.ndarray   # Nx3 float32
    normals: np.ndarray    # Nx3 float32
    faces: np.ndarray      # Mx3 uint32
    classifications: Optional[np.ndarray] = None  # Nx1 uint8


@dataclass
class TextureFrameData:
    """Parsed texture frame from LRAW format"""
    uuid: bytes
    timestamp: float
    transform: np.ndarray    # 4x4 float32
    intrinsics: np.ndarray   # 3x3 float32
    resolution: tuple        # (width, height)
    image_data: bytes        # JPEG/HEIC


@dataclass
class DepthFrameData:
    """Parsed depth frame from LRAW format"""
    uuid: bytes
    timestamp: float
    transform: np.ndarray    # 4x4 float32
    intrinsics: np.ndarray   # 3x3 float32
    width: int
    height: int
    depth_values: np.ndarray   # WxH float32
    confidence_values: Optional[np.ndarray] = None  # WxH uint8


@dataclass
class LRAWData:
    """Complete parsed LRAW file"""
    version: int
    flags: int
    mesh_anchors: list[MeshAnchorData]
    texture_frames: list[TextureFrameData]
    depth_frames: list[DepthFrameData]

    # Computed
    total_vertices: int = 0
    total_faces: int = 0


class LRAWFlags:
    """LRAW format flags"""
    HAS_CLASSIFICATIONS = 1 << 0
    HAS_CONFIDENCE_MAPS = 1 << 1
    HAS_TEXTURE_FRAMES = 1 << 2
    HAS_DEPTH_FRAMES = 1 << 3
    COMPRESSED = 1 << 4


class RawDataProcessor:
    """Processes raw scan data from iOS debug pipeline"""

    def __init__(self, output_dir: str = "./data/processed"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    async def process(
        self,
        raw_file_path: str,
        scan_id: str,
        progress_callback: Optional[Callable[[float, str, str], Awaitable[None]]] = None
    ) -> dict[str, Any]:
        """
        Process LRAW file and prepare data for standard pipeline.

        Returns dict with paths to processed data.
        """
        raw_path = Path(raw_file_path)

        if progress_callback:
            await progress_callback(0.0, "parsing_raw", "Parsing raw data...")

        # Parse LRAW file
        lraw_data = self.parse_lraw(raw_path)

        logger.info(
            f"Parsed LRAW: {len(lraw_data.mesh_anchors)} meshes, "
            f"{len(lraw_data.texture_frames)} textures, "
            f"{len(lraw_data.depth_frames)} depth frames"
        )

        if progress_callback:
            await progress_callback(0.1, "reconstructing_mesh", "Reconstructing mesh...")

        # Reconstruct combined mesh
        output_dir = self.output_dir / scan_id
        output_dir.mkdir(parents=True, exist_ok=True)

        mesh_path = await self._reconstruct_mesh(lraw_data, output_dir)

        if progress_callback:
            await progress_callback(0.2, "extracting_pointcloud", "Extracting point cloud...")

        # Extract point cloud from mesh
        pointcloud_path = await self._extract_pointcloud(lraw_data, output_dir)

        if progress_callback:
            await progress_callback(0.3, "processing_textures", "Processing textures...")

        # Save texture frames
        textures_dir = await self._save_textures(lraw_data, output_dir)

        if progress_callback:
            await progress_callback(0.4, "processing_depth", "Processing depth data...")

        # Process depth data
        depth_info = await self._process_depth_data(lraw_data, output_dir)

        if progress_callback:
            await progress_callback(0.5, "ai_depth_enhancement", "Running AI depth enhancement...")

        # AI depth enhancement (Depth Anything V2 + Fusion)
        ai_enhanced = await self._enhance_depth_with_ai(lraw_data, output_dir)

        if progress_callback:
            await progress_callback(0.6, "raw_processing_complete", "Raw data processing complete")

        result = {
            "mesh_path": str(mesh_path),
            "pointcloud_path": str(pointcloud_path),
            "textures_dir": str(textures_dir),
            "depth_info": depth_info,
            "statistics": {
                "mesh_anchors": len(lraw_data.mesh_anchors),
                "total_vertices": lraw_data.total_vertices,
                "total_faces": lraw_data.total_faces,
                "texture_frames": len(lraw_data.texture_frames),
                "depth_frames": len(lraw_data.depth_frames)
            }
        }

        # Add AI enhancement results if available
        if ai_enhanced:
            result["ai_enhanced"] = ai_enhanced
            result["enhanced_pointcloud_path"] = ai_enhanced["enhanced_pointcloud_path"]

        return result

    def parse_lraw(self, file_path: Path) -> LRAWData:
        """Parse LRAW binary format"""
        with open(file_path, "rb") as f:
            # Read header (32 bytes)
            header = f.read(32)

            magic = header[0:4]
            if magic != b"LRAW":
                raise ValueError(f"Invalid LRAW magic: {magic}")

            version = struct.unpack("<H", header[4:6])[0]
            flags = struct.unpack("<H", header[6:8])[0]
            mesh_count = struct.unpack("<I", header[8:12])[0]
            texture_count = struct.unpack("<I", header[12:16])[0]
            depth_count = struct.unpack("<I", header[16:20])[0]

            logger.debug(
                f"LRAW header: v{version}, flags={flags:04x}, "
                f"meshes={mesh_count}, textures={texture_count}, depth={depth_count}"
            )

            has_classifications = bool(flags & LRAWFlags.HAS_CLASSIFICATIONS)
            has_confidence = bool(flags & LRAWFlags.HAS_CONFIDENCE_MAPS)

            # Parse mesh anchors
            mesh_anchors = []
            total_vertices = 0
            total_faces = 0

            for i in range(mesh_count):
                anchor = self._parse_mesh_anchor(f, has_classifications)
                mesh_anchors.append(anchor)
                total_vertices += len(anchor.vertices)
                total_faces += len(anchor.faces)

            # Parse texture frames
            texture_frames = []
            for i in range(texture_count):
                frame = self._parse_texture_frame(f)
                texture_frames.append(frame)

            # Parse depth frames
            depth_frames = []
            for i in range(depth_count):
                frame = self._parse_depth_frame(f, has_confidence)
                depth_frames.append(frame)

            return LRAWData(
                version=version,
                flags=flags,
                mesh_anchors=mesh_anchors,
                texture_frames=texture_frames,
                depth_frames=depth_frames,
                total_vertices=total_vertices,
                total_faces=total_faces
            )

    def _parse_mesh_anchor(self, f, has_classifications: bool) -> MeshAnchorData:
        """Parse a single mesh anchor from binary stream"""
        # UUID (16 bytes)
        uuid = f.read(16)

        # Transform (64 bytes - 4x4 float32)
        transform_data = f.read(64)
        transform = np.frombuffer(transform_data, dtype=np.float32).reshape(4, 4)

        # Vertex count (4 bytes)
        vertex_count = struct.unpack("<I", f.read(4))[0]

        # Face count (4 bytes)
        face_count = struct.unpack("<I", f.read(4))[0]

        # Classification flag (1 byte)
        has_class = struct.unpack("<B", f.read(1))[0]

        # Vertices (vertex_count * 12 bytes)
        vertices_data = f.read(vertex_count * 12)
        vertices = np.frombuffer(vertices_data, dtype=np.float32).reshape(-1, 3)

        # Normals (vertex_count * 12 bytes)
        normals_data = f.read(vertex_count * 12)
        normals = np.frombuffer(normals_data, dtype=np.float32).reshape(-1, 3)

        # Faces (face_count * 12 bytes - 3 uint32 per face)
        faces_data = f.read(face_count * 12)
        faces = np.frombuffer(faces_data, dtype=np.uint32).reshape(-1, 3)

        # Classifications (optional)
        classifications = None
        if has_class and has_classifications:
            class_data = f.read(vertex_count)
            classifications = np.frombuffer(class_data, dtype=np.uint8)

        return MeshAnchorData(
            uuid=uuid,
            transform=transform,
            vertices=vertices,
            normals=normals,
            faces=faces,
            classifications=classifications
        )

    def _parse_texture_frame(self, f) -> TextureFrameData:
        """Parse a single texture frame from binary stream"""
        # UUID (16 bytes)
        uuid = f.read(16)

        # Timestamp (8 bytes)
        timestamp = struct.unpack("<d", f.read(8))[0]

        # Transform (64 bytes)
        transform_data = f.read(64)
        transform = np.frombuffer(transform_data, dtype=np.float32).reshape(4, 4)

        # Intrinsics (36 bytes - 3x3 float32)
        intrinsics_data = f.read(36)
        intrinsics = np.frombuffer(intrinsics_data, dtype=np.float32).reshape(3, 3)

        # Resolution (8 bytes - 2 uint32)
        width = struct.unpack("<I", f.read(4))[0]
        height = struct.unpack("<I", f.read(4))[0]

        # Image data length (4 bytes)
        image_length = struct.unpack("<I", f.read(4))[0]

        # Image data
        image_data = f.read(image_length)

        return TextureFrameData(
            uuid=uuid,
            timestamp=timestamp,
            transform=transform,
            intrinsics=intrinsics,
            resolution=(width, height),
            image_data=image_data
        )

    def _parse_depth_frame(self, f, has_confidence: bool) -> DepthFrameData:
        """Parse a single depth frame from binary stream"""
        # UUID (16 bytes)
        uuid = f.read(16)

        # Timestamp (8 bytes)
        timestamp = struct.unpack("<d", f.read(8))[0]

        # Transform (64 bytes)
        transform_data = f.read(64)
        transform = np.frombuffer(transform_data, dtype=np.float32).reshape(4, 4)

        # Intrinsics (36 bytes)
        intrinsics_data = f.read(36)
        intrinsics = np.frombuffer(intrinsics_data, dtype=np.float32).reshape(3, 3)

        # Dimensions (8 bytes)
        width = struct.unpack("<I", f.read(4))[0]
        height = struct.unpack("<I", f.read(4))[0]

        # Depth values (width * height * 4 bytes)
        depth_size = width * height * 4
        depth_data = f.read(depth_size)
        depth_values = np.frombuffer(depth_data, dtype=np.float32).reshape(height, width)

        # Confidence values (optional)
        confidence_values = None
        if has_confidence:
            conf_size = width * height
            conf_data = f.read(conf_size)
            if len(conf_data) == conf_size:
                confidence_values = np.frombuffer(conf_data, dtype=np.uint8).reshape(height, width)

        return DepthFrameData(
            uuid=uuid,
            timestamp=timestamp,
            transform=transform,
            intrinsics=intrinsics,
            width=width,
            height=height,
            depth_values=depth_values,
            confidence_values=confidence_values
        )

    async def _reconstruct_mesh(self, lraw_data: LRAWData, output_dir: Path) -> Path:
        """Reconstruct combined mesh from all anchors"""
        output_path = output_dir / "reconstructed_mesh.ply"

        # Combine all mesh anchors
        all_vertices = []
        all_normals = []
        all_faces = []
        vertex_offset = 0

        for anchor in lraw_data.mesh_anchors:
            # Transform vertices to world space
            transform = anchor.transform
            vertices = anchor.vertices

            # Apply transformation (homogeneous coordinates)
            ones = np.ones((len(vertices), 1), dtype=np.float32)
            homogeneous = np.hstack([vertices, ones])
            transformed = (transform @ homogeneous.T).T[:, :3]

            all_vertices.append(transformed)

            # Transform normals (rotation only)
            rotation = transform[:3, :3]
            transformed_normals = (rotation @ anchor.normals.T).T
            all_normals.append(transformed_normals)

            # Offset face indices
            all_faces.append(anchor.faces + vertex_offset)
            vertex_offset += len(vertices)

        # Concatenate all data
        combined_vertices = np.vstack(all_vertices)
        combined_normals = np.vstack(all_normals)
        combined_faces = np.vstack(all_faces)

        # Write PLY file
        self._write_ply(
            output_path,
            combined_vertices,
            combined_normals,
            combined_faces
        )

        logger.info(f"Reconstructed mesh: {len(combined_vertices)} vertices, {len(combined_faces)} faces")

        return output_path

    async def _extract_pointcloud(self, lraw_data: LRAWData, output_dir: Path) -> Path:
        """Extract point cloud from mesh and depth data"""
        output_path = output_dir / "pointcloud.ply"

        # Use mesh vertices as point cloud
        all_points = []
        all_colors = []

        for anchor in lraw_data.mesh_anchors:
            transform = anchor.transform
            vertices = anchor.vertices

            # Transform to world space
            ones = np.ones((len(vertices), 1), dtype=np.float32)
            homogeneous = np.hstack([vertices, ones])
            transformed = (transform @ homogeneous.T).T[:, :3]

            all_points.append(transformed)

            # Default color (white)
            colors = np.ones((len(vertices), 3), dtype=np.uint8) * 200
            all_colors.append(colors)

        combined_points = np.vstack(all_points)
        combined_colors = np.vstack(all_colors)

        # Write point cloud PLY
        self._write_pointcloud_ply(output_path, combined_points, combined_colors)

        logger.info(f"Extracted point cloud: {len(combined_points)} points")

        return output_path

    async def _save_textures(self, lraw_data: LRAWData, output_dir: Path) -> Path:
        """Save texture frames to disk"""
        textures_dir = output_dir / "textures"
        textures_dir.mkdir(exist_ok=True)

        for i, frame in enumerate(lraw_data.texture_frames):
            # Determine format from data
            if frame.image_data[:2] == b'\xff\xd8':
                ext = "jpg"
            elif frame.image_data[:4] == b'\x00\x00\x00\x0c':
                ext = "heic"
            else:
                ext = "bin"

            output_path = textures_dir / f"frame_{i:04d}.{ext}"
            with open(output_path, "wb") as f:
                f.write(frame.image_data)

            # Save camera metadata
            meta_path = textures_dir / f"frame_{i:04d}_camera.npz"
            np.savez(
                meta_path,
                transform=frame.transform,
                intrinsics=frame.intrinsics,
                timestamp=frame.timestamp,
                resolution=frame.resolution
            )

        logger.info(f"Saved {len(lraw_data.texture_frames)} texture frames")

        return textures_dir

    async def _process_depth_data(self, lraw_data: LRAWData, output_dir: Path) -> dict:
        """Process and save depth data"""
        depth_dir = output_dir / "depth"
        depth_dir.mkdir(exist_ok=True)

        depth_stats = []

        for i, frame in enumerate(lraw_data.depth_frames):
            # Save depth map
            depth_path = depth_dir / f"depth_{i:04d}.npz"
            np.savez(
                depth_path,
                depth=frame.depth_values,
                transform=frame.transform,
                intrinsics=frame.intrinsics,
                timestamp=frame.timestamp,
                confidence=frame.confidence_values
            )

            # Compute statistics
            valid_depth = frame.depth_values[np.isfinite(frame.depth_values) & (frame.depth_values > 0)]
            if len(valid_depth) > 0:
                depth_stats.append({
                    "frame": i,
                    "min": float(valid_depth.min()),
                    "max": float(valid_depth.max()),
                    "mean": float(valid_depth.mean()),
                    "valid_ratio": len(valid_depth) / frame.depth_values.size
                })

        logger.info(f"Processed {len(lraw_data.depth_frames)} depth frames")

        return {
            "depth_dir": str(depth_dir),
            "frame_count": len(lraw_data.depth_frames),
            "statistics": depth_stats
        }

    def _write_ply(
        self,
        path: Path,
        vertices: np.ndarray,
        normals: np.ndarray,
        faces: np.ndarray
    ):
        """Write mesh to PLY format"""
        with open(path, "w") as f:
            # Header
            f.write("ply\n")
            f.write("format ascii 1.0\n")
            f.write(f"element vertex {len(vertices)}\n")
            f.write("property float x\n")
            f.write("property float y\n")
            f.write("property float z\n")
            f.write("property float nx\n")
            f.write("property float ny\n")
            f.write("property float nz\n")
            f.write(f"element face {len(faces)}\n")
            f.write("property list uchar int vertex_indices\n")
            f.write("end_header\n")

            # Vertices with normals
            for v, n in zip(vertices, normals):
                f.write(f"{v[0]:.6f} {v[1]:.6f} {v[2]:.6f} {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")

            # Faces
            for face in faces:
                f.write(f"3 {face[0]} {face[1]} {face[2]}\n")

    def _write_pointcloud_ply(
        self,
        path: Path,
        points: np.ndarray,
        colors: np.ndarray
    ):
        """Write point cloud to PLY format"""
        with open(path, "w") as f:
            # Header
            f.write("ply\n")
            f.write("format ascii 1.0\n")
            f.write(f"element vertex {len(points)}\n")
            f.write("property float x\n")
            f.write("property float y\n")
            f.write("property float z\n")
            f.write("property uchar red\n")
            f.write("property uchar green\n")
            f.write("property uchar blue\n")
            f.write("end_header\n")

            # Points with colors
            for p, c in zip(points, colors):
                f.write(f"{p[0]:.6f} {p[1]:.6f} {p[2]:.6f} {c[0]} {c[1]} {c[2]}\n")

    async def _enhance_depth_with_ai(
        self,
        lraw_data: LRAWData,
        output_dir: Path
    ) -> Optional[dict]:
        """
        Enhance depth data using AI (Depth Anything V2 + Fusion).

        This replicates the iOS edge ML pipeline on the backend:
        1. Run Depth Anything V2 on RGB frames
        2. Fuse with LiDAR depth
        3. Generate enhanced point cloud

        Returns dict with paths to enhanced data, or None if AI not available.
        """
        if not _ensure_depth_services():
            logger.info("Skipping AI depth enhancement (services not available)")
            return None

        if not lraw_data.texture_frames or not lraw_data.depth_frames:
            logger.warning("No texture or depth frames for AI enhancement")
            return None

        try:
            from PIL import Image
            import io

            enhanced_dir = output_dir / "enhanced_depth"
            enhanced_dir.mkdir(exist_ok=True)

            fusion_results = []
            all_enhanced_points = []
            all_enhanced_colors = []

            # Match texture frames with closest depth frames by timestamp
            for i, texture_frame in enumerate(lraw_data.texture_frames):
                # Find closest depth frame
                closest_depth = min(
                    lraw_data.depth_frames,
                    key=lambda d: abs(d.timestamp - texture_frame.timestamp)
                )

                # Load RGB image
                try:
                    img = Image.open(io.BytesIO(texture_frame.image_data))
                    rgb_array = np.array(img.convert("RGB"))
                except Exception as e:
                    logger.warning(f"Failed to decode texture frame {i}: {e}")
                    continue

                # Run Depth Anything V2
                logger.debug(f"Processing frame {i} with Depth Anything V2...")
                ai_depth = _depth_anything_service.predict(rgb_array)

                if ai_depth is None:
                    logger.warning(f"AI depth prediction failed for frame {i}")
                    continue

                # Fuse with LiDAR
                fusion_result = _depth_fusion_service.fuse(
                    lidar_depth=closest_depth.depth_values,
                    ai_depth=ai_depth,
                    lidar_confidence=closest_depth.confidence_values
                )

                if fusion_result is None:
                    logger.warning(f"Depth fusion failed for frame {i}")
                    continue

                # Save fused depth
                fused_path = enhanced_dir / f"fused_{i:04d}.npz"
                np.savez(
                    fused_path,
                    fused_depth=fusion_result.fused_depth,
                    confidence=fusion_result.confidence_map,
                    ai_depth=ai_depth,
                    lidar_resolution=fusion_result.lidar_resolution,
                    output_resolution=fusion_result.output_resolution
                )

                fusion_results.append({
                    "frame": i,
                    "lidar_coverage": fusion_result.stats.lidar_coverage,
                    "ai_contribution": fusion_result.stats.ai_contribution,
                    "processing_time_ms": fusion_result.stats.processing_time_ms
                })

                # Extract enhanced point cloud from fused depth
                from services.depth_fusion import PointCloudExtractor

                extractor = PointCloudExtractor(min_confidence=0.3, max_points=500_000)
                points, colors, _ = extractor.extract(
                    depth=fusion_result.fused_depth,
                    confidence=fusion_result.confidence_map,
                    intrinsics=texture_frame.intrinsics,
                    transform=texture_frame.transform,
                    rgb_image=rgb_array
                )

                if points is not None and len(points) > 0:
                    all_enhanced_points.append(points)
                    if colors is not None:
                        all_enhanced_colors.append(colors)
                    else:
                        all_enhanced_colors.append(
                            np.ones((len(points), 3), dtype=np.uint8) * 200
                        )

                logger.debug(
                    f"Frame {i}: {len(points)} points, "
                    f"LiDAR coverage: {fusion_result.stats.lidar_coverage:.1%}"
                )

            # Combine enhanced point clouds
            if all_enhanced_points:
                combined_points = np.vstack(all_enhanced_points)
                combined_colors = np.vstack(all_enhanced_colors)

                # Save enhanced point cloud
                enhanced_pc_path = output_dir / "enhanced_pointcloud.ply"
                self._write_pointcloud_ply(enhanced_pc_path, combined_points, combined_colors)

                logger.info(
                    f"AI-enhanced point cloud: {len(combined_points)} points "
                    f"from {len(fusion_results)} frames"
                )

                return {
                    "enhanced_pointcloud_path": str(enhanced_pc_path),
                    "enhanced_depth_dir": str(enhanced_dir),
                    "frames_processed": len(fusion_results),
                    "total_points": len(combined_points),
                    "fusion_stats": fusion_results
                }

            return None

        except Exception as e:
            logger.error(f"AI depth enhancement failed: {e}")
            import traceback
            traceback.print_exc()
            return None
