import simd

// MARK: - simd_float3 Extensions

extension simd_float3 {
    /// Zero vector
    static let zero = simd_float3(0, 0, 0)

    /// Unit vector along X axis
    static let unitX = simd_float3(1, 0, 0)

    /// Unit vector along Y axis
    static let unitY = simd_float3(0, 1, 0)

    /// Unit vector along Z axis
    static let unitZ = simd_float3(0, 0, 1)

    /// Create from simd_float4 (ignoring w component)
    init(_ v: simd_float4) {
        self.init(v.x, v.y, v.z)
    }

    /// Distance to another point
    func distance(to other: simd_float3) -> Float {
        simd_distance(self, other)
    }

    /// Normalized vector
    var normalized: simd_float3 {
        simd_normalize(self)
    }

    /// Length/magnitude of vector
    var length: Float {
        simd_length(self)
    }

    /// Squared length (faster than length for comparisons)
    var lengthSquared: Float {
        simd_length_squared(self)
    }
}

// MARK: - simd_float4 Extensions

extension simd_float4 {
    /// Zero vector
    static let zero = simd_float4(0, 0, 0, 0)

    /// Create from simd_float3 with w = 1 (point)
    init(_ v: simd_float3, _ w: Float = 1) {
        self.init(v.x, v.y, v.z, w)
    }

    /// Get xyz components as simd_float3
    var xyz: simd_float3 {
        simd_float3(x, y, z)
    }
}

// MARK: - simd_float4x4 Extensions

extension simd_float4x4 {
    /// Identity matrix
    static let identity = matrix_identity_float4x4

    /// Extract translation component
    var translation: simd_float3 {
        simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Extract rotation matrix (upper 3x3)
    var rotation: simd_float3x3 {
        simd_float3x3(
            simd_float3(columns.0.x, columns.0.y, columns.0.z),
            simd_float3(columns.1.x, columns.1.y, columns.1.z),
            simd_float3(columns.2.x, columns.2.y, columns.2.z)
        )
    }

    /// Create translation matrix
    static func translation(_ t: simd_float3) -> simd_float4x4 {
        simd_float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(t.x, t.y, t.z, 1)
        )
    }

    /// Create uniform scale matrix
    static func scale(_ s: Float) -> simd_float4x4 {
        simd_float4x4(
            simd_float4(s, 0, 0, 0),
            simd_float4(0, s, 0, 0),
            simd_float4(0, 0, s, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    /// Create non-uniform scale matrix
    static func scale(_ s: simd_float3) -> simd_float4x4 {
        simd_float4x4(
            simd_float4(s.x, 0, 0, 0),
            simd_float4(0, s.y, 0, 0),
            simd_float4(0, 0, s.z, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    /// Create rotation matrix around X axis
    static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, c, s, 0),
            simd_float4(0, -s, c, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    /// Create rotation matrix around Y axis
    static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            simd_float4(c, 0, -s, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(s, 0, c, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    /// Create rotation matrix around Z axis
    static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            simd_float4(c, s, 0, 0),
            simd_float4(-s, c, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
}

// MARK: - simd_float3x3 Extensions

extension simd_float3x3 {
    /// Identity matrix
    static let identity = matrix_identity_float3x3

    /// Determinant of the matrix
    var determinant: Float {
        simd_determinant(self)
    }

    /// Transpose of the matrix
    var transposed: simd_float3x3 {
        simd_transpose(self)
    }

    /// Inverse of the matrix
    var inverse: simd_float3x3 {
        simd_inverse(self)
    }
}

// MARK: - SIMD3<Int> Hashable

extension SIMD3: Hashable where Scalar == Int {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}
