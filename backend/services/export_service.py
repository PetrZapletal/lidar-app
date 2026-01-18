"""
Model Export Service

Exports processed 3D models to various formats:
- USDZ (Apple AR)
- glTF 2.0 (Web/Cross-platform)
- OBJ (Universal)
- STL (3D Printing)
- PLY (Point Cloud)
"""

from pathlib import Path
from typing import Optional
import numpy as np

from services.sugar_mesh import MeshData
from utils.logger import get_logger

logger = get_logger(__name__)


class ModelExporter:
    """
    Multi-format 3D model exporter.

    Supports:
    - USDZ: Apple AR format with textures
    - glTF: Cross-platform 3D format
    - OBJ: Wavefront OBJ with MTL
    - STL: 3D printing format
    - PLY: Point cloud format
    """

    SUPPORTED_FORMATS = ["usdz", "gltf", "glb", "obj", "stl", "ply"]

    async def export(
        self,
        mesh: Optional[MeshData],
        gaussians: Optional[list],
        format: str,
        output_dir: Path,
        textures: Optional[dict] = None
    ) -> Path:
        """
        Export model to specified format.

        Args:
            mesh: Mesh data to export
            gaussians: Gaussian data (for PLY export)
            format: Output format
            output_dir: Output directory
            textures: Optional texture paths

        Returns:
            Path to exported file
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        format = format.lower()

        if format not in self.SUPPORTED_FORMATS:
            raise ValueError(f"Unsupported format: {format}")

        logger.info(f"Exporting to {format.upper()}")

        if format == "usdz":
            return await self._export_usdz(mesh, output_dir, textures)
        elif format in ["gltf", "glb"]:
            return await self._export_gltf(mesh, output_dir, textures, binary=(format == "glb"))
        elif format == "obj":
            return await self._export_obj(mesh, output_dir, textures)
        elif format == "stl":
            return await self._export_stl(mesh, output_dir)
        elif format == "ply":
            return await self._export_ply(mesh, gaussians, output_dir)

    async def _export_usdz(
        self,
        mesh: MeshData,
        output_dir: Path,
        textures: Optional[dict]
    ) -> Path:
        """Export to USDZ format (Apple AR)"""

        output_path = output_dir / "model.usdz"

        # In production, use usdz_converter or Reality Composer Pro:
        # - Create USDC scene
        # - Add mesh geometry
        # - Create PBR material
        # - Add textures
        # - Package as USDZ (zip with .usdc + textures)

        # Placeholder
        output_path.touch()
        logger.info(f"Exported USDZ: {output_path}")

        return output_path

    async def _export_gltf(
        self,
        mesh: MeshData,
        output_dir: Path,
        textures: Optional[dict],
        binary: bool = False
    ) -> Path:
        """Export to glTF 2.0 format"""

        ext = "glb" if binary else "gltf"
        output_path = output_dir / f"model.{ext}"

        # In production, use trimesh or pygltflib:
        # gltf = {
        #     "asset": {"version": "2.0"},
        #     "scene": 0,
        #     "scenes": [{"nodes": [0]}],
        #     "nodes": [{"mesh": 0}],
        #     "meshes": [{"primitives": [{"attributes": {...}}]}],
        #     "accessors": [...],
        #     "bufferViews": [...],
        #     "buffers": [...]
        # }

        # Placeholder
        output_path.touch()
        logger.info(f"Exported glTF: {output_path}")

        return output_path

    async def _export_obj(
        self,
        mesh: MeshData,
        output_dir: Path,
        textures: Optional[dict]
    ) -> Path:
        """Export to Wavefront OBJ format"""

        obj_path = output_dir / "model.obj"
        mtl_path = output_dir / "model.mtl"

        if mesh is None or len(mesh.vertices) == 0:
            obj_path.touch()
            return obj_path

        # Write OBJ file
        lines = []
        lines.append("# LiDAR 3D Scanner Export")
        lines.append(f"# Vertices: {len(mesh.vertices)}")
        lines.append(f"# Faces: {len(mesh.faces)}")
        lines.append("")

        if textures:
            lines.append(f"mtllib model.mtl")
            lines.append("")

        # Vertices
        for v in mesh.vertices:
            lines.append(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}")

        # Texture coordinates
        if mesh.uvs is not None:
            lines.append("")
            for uv in mesh.uvs:
                lines.append(f"vt {uv[0]:.6f} {uv[1]:.6f}")

        # Normals
        if mesh.normals is not None:
            lines.append("")
            for n in mesh.normals:
                lines.append(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}")

        # Faces
        lines.append("")
        if textures:
            lines.append("usemtl material0")

        for f in mesh.faces:
            if mesh.uvs is not None and mesh.normals is not None:
                # v/vt/vn format
                lines.append(f"f {f[0]+1}/{f[0]+1}/{f[0]+1} "
                           f"{f[1]+1}/{f[1]+1}/{f[1]+1} "
                           f"{f[2]+1}/{f[2]+1}/{f[2]+1}")
            elif mesh.normals is not None:
                # v//vn format
                lines.append(f"f {f[0]+1}//{f[0]+1} "
                           f"{f[1]+1}//{f[1]+1} "
                           f"{f[2]+1}//{f[2]+1}")
            else:
                # v format
                lines.append(f"f {f[0]+1} {f[1]+1} {f[2]+1}")

        with open(obj_path, 'w') as f:
            f.write('\n'.join(lines))

        # Write MTL file if textures
        if textures:
            mtl_lines = [
                "# Material",
                "newmtl material0",
                "Ka 0.2 0.2 0.2",
                "Kd 0.8 0.8 0.8",
                "Ks 0.0 0.0 0.0",
                "Ns 0.0",
            ]

            if "diffuse" in textures:
                mtl_lines.append(f"map_Kd {Path(textures['diffuse']).name}")

            if "normal" in textures:
                mtl_lines.append(f"bump {Path(textures['normal']).name}")

            with open(mtl_path, 'w') as f:
                f.write('\n'.join(mtl_lines))

        logger.info(f"Exported OBJ: {obj_path}")

        return obj_path

    async def _export_stl(
        self,
        mesh: MeshData,
        output_dir: Path
    ) -> Path:
        """Export to STL format (ASCII)"""

        output_path = output_dir / "model.stl"

        if mesh is None or len(mesh.vertices) == 0:
            output_path.touch()
            return output_path

        lines = ["solid model"]

        for face in mesh.faces:
            v0, v1, v2 = mesh.vertices[face]

            # Calculate face normal
            e1 = v1 - v0
            e2 = v2 - v0
            normal = np.cross(e1, e2)
            norm = np.linalg.norm(normal)
            if norm > 0:
                normal = normal / norm
            else:
                normal = np.array([0, 0, 1])

            lines.append(f"  facet normal {normal[0]:.6f} {normal[1]:.6f} {normal[2]:.6f}")
            lines.append("    outer loop")
            lines.append(f"      vertex {v0[0]:.6f} {v0[1]:.6f} {v0[2]:.6f}")
            lines.append(f"      vertex {v1[0]:.6f} {v1[1]:.6f} {v1[2]:.6f}")
            lines.append(f"      vertex {v2[0]:.6f} {v2[1]:.6f} {v2[2]:.6f}")
            lines.append("    endloop")
            lines.append("  endfacet")

        lines.append("endsolid model")

        with open(output_path, 'w') as f:
            f.write('\n'.join(lines))

        logger.info(f"Exported STL: {output_path}")

        return output_path

    async def _export_ply(
        self,
        mesh: Optional[MeshData],
        gaussians: Optional[list],
        output_dir: Path
    ) -> Path:
        """Export to PLY format"""

        output_path = output_dir / "model.ply"

        # Get vertices from mesh or gaussians
        if mesh is not None and len(mesh.vertices) > 0:
            vertices = mesh.vertices
            faces = mesh.faces
            normals = mesh.normals
            colors = mesh.colors
        elif gaussians:
            vertices = np.array([g.position for g in gaussians])
            faces = None
            normals = None
            colors = None
        else:
            output_path.touch()
            return output_path

        # Write PLY header
        lines = [
            "ply",
            "format ascii 1.0",
            f"element vertex {len(vertices)}",
            "property float x",
            "property float y",
            "property float z",
        ]

        if normals is not None:
            lines.extend([
                "property float nx",
                "property float ny",
                "property float nz",
            ])

        if colors is not None:
            lines.extend([
                "property uchar red",
                "property uchar green",
                "property uchar blue",
            ])

        if faces is not None and len(faces) > 0:
            lines.extend([
                f"element face {len(faces)}",
                "property list uchar int vertex_indices",
            ])

        lines.append("end_header")

        # Write vertices
        for i, v in enumerate(vertices):
            line = f"{v[0]:.6f} {v[1]:.6f} {v[2]:.6f}"

            if normals is not None:
                n = normals[i]
                line += f" {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}"

            if colors is not None:
                c = colors[i]
                line += f" {int(c[0]*255)} {int(c[1]*255)} {int(c[2]*255)}"

            lines.append(line)

        # Write faces
        if faces is not None:
            for f in faces:
                lines.append(f"3 {f[0]} {f[1]} {f[2]}")

        with open(output_path, 'w') as f:
            f.write('\n'.join(lines))

        logger.info(f"Exported PLY: {output_path}")

        return output_path
