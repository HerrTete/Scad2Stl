import Foundation

public struct MetalShaders {
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float4x4 modelMatrix;
        float4x4 viewMatrix;
        float3 cameraPosition;
        float4 defaultColor;
        float4 wireColor;
        int showWireframe;
    };

    struct VertexIn {
        float3 position  [[attribute(0)]];
        float3 normal    [[attribute(1)]];
        float4 color     [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldNormal;
        float3 worldPosition;
        float4 color;
    };

    vertex VertexOut cadVertexShader(VertexIn in [[stage_in]],
                                     constant Uniforms &u [[buffer(1)]]) {
        VertexOut out;
        float4 worldPos = u.modelMatrix * float4(in.position, 1.0);
        out.position = u.modelViewProjectionMatrix * float4(in.position, 1.0);
        out.worldPosition = worldPos.xyz;
        out.worldNormal = (u.modelMatrix * float4(in.normal, 0.0)).xyz;
        out.color = (in.color.a > 0.0) ? in.color : u.defaultColor;
        return out;
    }

    fragment float4 cadFragmentShader(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(1)]]) {
        // Compute normal (either interpolated vertex normal or facet normal fallback)
        float3 N = length_squared(in.worldNormal) > 0.1 ? normalize(in.worldNormal) : normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
        
        // Headlight direction from camera to surface
        float3 V = normalize(u.cameraPosition - in.worldPosition);
        float3 L1 = V; // Headlight
        float3 L2 = normalize(float3(0.5, 0.5, 1.0)); // Top-right overhead CAD key light
        
        // Two-sided diffuse lighting
        float diff1 = abs(dot(N, L1));
        float diff2 = max(dot(N, L2), 0.0);
        float diffuse = diff1 * 0.6 + diff2 * 0.4;
        
        // Blinn-phong specular
        float3 H = normalize(L2 + V);
        float spec = pow(max(dot(N, H), 0.0), 32.0) * 0.25;
        
        float ambient = 0.22;
        float3 baseRgb = in.color.rgb;
        float3 litRgb = baseRgb * (ambient + diffuse * 0.75) + float3(spec);
        
        return float4(litRgb, in.color.a);
    }

    // MARK: - Line/Grid Shaders
    struct LineVertexIn {
        float3 position [[attribute(0)]];
        float4 color    [[attribute(1)]];
    };

    struct LineVertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex LineVertexOut lineVertexShader(LineVertexIn in [[stage_in]],
                                          constant Uniforms &u [[buffer(1)]]) {
        LineVertexOut out;
        out.position = u.modelViewProjectionMatrix * float4(in.position, 1.0);
        out.color = in.color;
        return out;
    }

    fragment float4 lineFragmentShader(LineVertexOut in [[stage_in]]) {
        return in.color;
    }
    """
}
